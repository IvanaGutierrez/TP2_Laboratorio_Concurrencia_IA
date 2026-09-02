-- =========================================================
-- restricciones_integridad.sql — Food Store
-- Restricciones de integridad adicionales (reglas de negocio
-- que hoy dependen de la aplicación y no están garantizadas
-- por el motor ni por los triggers existentes).
--
-- Este script se aplica SOLO sobre una copia de trabajo de la
-- base (copia_trabajo), nunca directamente sobre food_store.
--
-- Protocolo de ejecución: envolver en BEGIN; ... ROLLBACK; para
-- inspección, o COMMIT; para persistir.
--
--   BEGIN;
--   \i restricciones_integridad.sql
--   -- probar, inspeccionar ...
--   ROLLBACK;  -- o COMMIT;
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


-- PRUEBAS REGLA 1
-- -----------------------------------------------------------------
-- Ejecutar cada bloque individualmente dentro de BEGIN; / ROLLBACK;
--
-- PRUEBA 1A — Debe FALLAR: retroceso de CONFIRMADO a PENDIENTE
UPDATE pedido SET estado = 'PENDIENTE' WHERE id = 1;
-- esperado: ERROR: Transición inválida: CONFIRMADO → PENDIENTE
--           (solo se permite → TERMINADO o → CANCELADO)
--
-- PRUEBA 1B — Debe PASAR: avance válido de CONFIRMADO a TERMINADO
UPDATE pedido SET estado = 'TERMINADO' WHERE id = 8;
-- esperado: UPDATE 1 (éxito, pedido 8 pasa de CONFIRMADO a TERMINADO)
-- -----------------------------------------------------------------


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


-- PRUEBAS REGLA 2
-- -----------------------------------------------------------------
-- Ejecutar cada bloque individualmente dentro de BEGIN; / ROLLBACK;
--
-- PRUEBA 2A — Debe FALLAR: insertar detalle en pedido CONFIRMADO
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
VALUES (1, 3, 1);
-- esperado: ERROR: No se pueden modificar detalles de un pedido
--           en estado CONFIRMADO (pedido 1)
--
-- PRUEBA 2B — Debe PASAR: insertar detalle en pedido PENDIENTE
-- Primero crear un pedido en estado PENDIENTE (default del enum)
INSERT INTO pedido (forma_pago, usuario_id)
VALUES ('EFECTIVO', 2)
RETURNING id;
-- Anotar el id retornado (ej: 11), y luego:
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
VALUES (11, 3, 1);
-- esperado: INSERT 0 1 (éxito — el trigger trg_subtotal congela
--           precio y calcula subtotal automáticamente)
-- -----------------------------------------------------------------
