-- =========================================================
-- aplicar_restricciones.sql — Food Store
-- Aplica SOLO las restricciones de integridad (Parte 1 del TP)
-- sobre la copia de trabajo. NO incluye las pruebas.
--
-- Uso (protocolo Parte 0):
--   1. Respaldo:  pg_dump -Fc copia_trabajo > respaldo_pre_alter.dump
--   2. Aplicar dentro de transacción:
--        BEGIN;
--        \i aplicar_restricciones.sql     (o ejecutar este archivo con -f)
--        COMMIT;
--   3. Verificar con restricciones_integridad_test.sql (en ROLLBACK).
-- =========================================================

-- =========================================================
-- REGLA 1: pedido.estado — Transiciones de estado sin retroceso
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