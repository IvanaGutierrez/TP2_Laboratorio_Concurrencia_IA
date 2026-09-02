-- =========================================================
-- restricciones_integridad_test.sql — Food Store
-- Test de las restricciones de integridad de la Parte 1 del TP.
--
-- Este archivo NO toca food_store: ejecutar sobre copia_trabajo.
-- Envuelve TODO el contenido de restricciones_integridad.sql más las
-- 4 pruebas (1A, 1B, 2A, 2B) en UNA transacción que termina en ROLLBACK:
-- nada persiste después de ejecutarlo.
--
-- Cómo ejecutar (psql):
--   psql -U postgres -d copia_trabajo -f restricciones_integridad_test.sql
--
-- OJO con ON_ERROR_STOP: dejarlo APAGADO (default). Las pruebas 1A y 2A
-- fallan A PROPÓSITO; cada una está protegida con un SAVEPOINT + 
-- ROLLBACK TO SAVEPOINT para que el error no aborte la transacción.
--
-- En DBeaver: abrir la SQL Editor de copia_trabajo y ejecutar el archivo
-- completo (o por bloques) — los SAVEPOINT permiten continuar tras el error.
--
-- NOTA: si se edita restricciones_integridad.sql, regenerar este archivo
-- (aquí está embebido su contenido para poder correrse de punta a punta).
-- =========================================================

BEGIN;

-- =========================================================
-- 1) APLICAR LAS RESTRICCIONES (funciones + triggers)
--    (contenido de restricciones_integridad.sql)
-- =========================================================

-- =========================================================
-- REGLA 1: pedido.estado — Transiciones de estado sin retroceso
--
-- SPEC: Un pedido solo puede avanzar de estado. La secuencia
-- válida es PENDIENTE → CONFIRMADO → TERMINADO.
-- CANCELADO es un estado terminal que solo puede alcanzarse
-- desde PENDIENTE o CONFIRMADO. TERMINADO es terminal.
-- Un pedido en estado TERMINADO o CANCELADO no puede cambiar
-- de estado.
--
-- JUSTIFICACIÓN: El tipo enum estado_pedido (schema.sql:10)
-- restringe los valores permitidos a
-- {'PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO'} pero NO
-- valida el orden de transición. Hoy la aplicación podría hacer
-- UPDATE pedido SET estado = 'PENDIENTE' WHERE id = 1 sobre un
-- pedido CONFIRMADO, retrocediéndolo sin control. No existe CHECK
-- ni trigger que lo impida: schema.sql solo define el DEFAULT
-- (línea 55) y objects.sql no tiene ningún trigger sobre la tabla
-- pedido — solo tiene triggers sobre detalle_pedido (subtotal,
-- total).
--
-- Tipo: TRIGGER (requiere comparar OLD.estado vs NEW.estado)
-- =========================================================

DROP FUNCTION IF EXISTS fn_validar_transicion_estado() CASCADE;

CREATE OR REPLACE FUNCTION fn_validar_transicion_estado()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.estado = NEW.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'TERMINADO' THEN
        RAISE EXCEPTION 'No se puede cambiar el estado de un pedido TERMINADO (pedido %)', NEW.id;
    END IF;

    IF OLD.estado = 'CANCELADO' THEN
        RAISE EXCEPTION 'No se puede cambiar el estado de un pedido CANCELADO (pedido %)', NEW.id;
    END IF;

    IF OLD.estado = 'PENDIENTE' AND NEW.estado NOT IN ('CONFIRMADO', 'CANCELADO') THEN
        RAISE EXCEPTION 'Transición inválida: PENDIENTE → % (solo se permite → CONFIRMADO o → CANCELADO)', NEW.estado;
    END IF;

    IF OLD.estado = 'CONFIRMADO' AND NEW.estado NOT IN ('TERMINADO', 'CANCELADO') THEN
        RAISE EXCEPTION 'Transición inválida: CONFIRMADO → % (solo se permite → TERMINADO o → CANCELADO)', NEW.estado;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_estado ON pedido;

CREATE TRIGGER trg_validar_estado
BEFORE UPDATE OF estado ON pedido
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION fn_validar_transicion_estado();

-- =========================================================
-- REGLA 2: detalle_pedido — Bloqueo de detalle en pedido cerrado
--
-- SPEC: No se pueden agregar ni modificar líneas de detalle
-- (cantidad, precio_unitario, etc.) de un pedido cuyo estado
-- es CONFIRMADO, TERMINADO o CANCELADO. Solo los pedidos en
-- estado PENDIENTE aceptan INSERT o UPDATE en sus detalles.
--
-- JUSTIFICACIÓN: En un food store, una vez que el pedido fue
-- confirmado o terminado, los items están definidos y no deben
-- editarse. El procedure sp_crear_pedido (objects.sql:89) solo
-- crea pedidos nuevos (siempre PENDIENTE), pero no hay
-- restricción en la BD que impida un INSERT o UPDATE directo
-- sobre detalle_pedido de un pedido CONFIRMADO. Los triggers
-- existentes sobre detalle_pedido son trg_subtotal (línea 61)
-- y trg_total_ins/trg_total_upd (líneas 77-85) — ninguno
-- verifica el estado del pedido padre.
--
-- Tipo: TRIGGER (necesita consultar tabla pedido padre)
-- =========================================================

DROP FUNCTION IF EXISTS fn_bloquear_detalle_pedido_cerrado() CASCADE;

CREATE OR REPLACE FUNCTION fn_bloquear_detalle_pedido_cerrado()
RETURNS TRIGGER AS $$
DECLARE
    v_estado estado_pedido;
BEGIN
    SELECT estado INTO v_estado
    FROM pedido
    WHERE id = NEW.pedido_id;

    IF v_estado IN ('CONFIRMADO', 'TERMINADO', 'CANCELADO') THEN
        RAISE EXCEPTION 'No se pueden modificar detalles de un pedido en estado % (pedido %)',
            v_estado, NEW.pedido_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bloquear_detalle_cerrado ON detalle_pedido;

CREATE TRIGGER trg_bloquear_detalle_cerrado
BEFORE INSERT OR UPDATE ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_bloquear_detalle_pedido_cerrado();


-- =========================================================
-- 2) PRUEBAS — una que DEBE FALLAR y una que DEBE PASAR por regla
-- =========================================================

-- ---------------------------------------------------------
-- PRUEBA 1A — ESPERADO: DEBE FALLAR
--   UPDATE pedido SET estado = 'PENDIENTE' WHERE id = 1
--   Pedido 1 está CONFIRMADO en el seed → retroceso CONFIRMADO → PENDIENTE,
--   viola la transición de estado de la REGLA 1.
--   Esperado: ERROR: Transición inválida: CONFIRMADO → PENDIENTE
--             (solo se permite → TERMINADO o → CANCELADO)
--   Si en cambio ve "UPDATE 1" sin error ⇒ la regla NO se aplicó (mal).
-- ---------------------------------------------------------
SAVEPOINT sp_prueba_1a;
UPDATE pedido SET estado = 'PENDIENTE' WHERE id = 1;
ROLLBACK TO SAVEPOINT sp_prueba_1a;

-- ---------------------------------------------------------
-- PRUEBA 1B — ESPERADO: DEBE PASAR
--   UPDATE pedido SET estado = 'TERMINADO' WHERE id = 8
--   Pedido 8 está CONFIRMADO en el seed → avance válido
--   CONFIRMADO → TERMINADO.
--   Esperado: UPDATE 1 (sin error).
-- ---------------------------------------------------------
UPDATE pedido SET estado = 'TERMINADO' WHERE id = 8;

-- ---------------------------------------------------------
-- PRUEBA 2A — ESPERADO: DEBE FALLAR
--   INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
--   VALUES (1, 3, 1)
--   Pedido 1 está CONFIRMADO → viola la REGLA 2 (bloqueo de detalle
--   en pedido cerrado). Producto 3 (Napolitana) existe y no está en
--   pedido 1, así que el error viene del trigger, no del UNIQUE.
--   Esperado: ERROR: No se pueden modificar detalles de un pedido
--             en estado CONFIRMADO (pedido 1)
-- ---------------------------------------------------------
SAVEPOINT sp_prueba_2a;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (1, 3, 1);
ROLLBACK TO SAVEPOINT sp_prueba_2a;

-- ---------------------------------------------------------
-- PRUEBA 2B — ESPERADO: DEBE PASAR
--   1) Crear un pedido nuevo (default: PENDIENTE) → queda editable.
--   2) Insertar un detalle en ese pedido PENDIENTE.
--   Esperado: INSERT 0 1 (pedido id retornado) + INSERT 0 1 (detalle).
--   En base fresca (seed de 10 pedidos) el id nuevo es 11; si el
--   RETURNING devuelve otro, usar ESE id en el segundo INSERT.
-- ---------------------------------------------------------
INSERT INTO pedido (forma_pago, usuario_id)
VALUES ('EFECTIVO', 2)
RETURNING id;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
VALUES (11, 3, 1);

-- =========================================================
-- FIN: REVERTIR TODO — nada de lo anterior persiste.
-- (Para inspección se pudo correr con ROLLBACK; si se quisiera
--  persistir las restricciones, habría que cambiar por COMMIT y
--  correr 1B/2B como verificación previa por separado.)
-- =========================================================
ROLLBACK;