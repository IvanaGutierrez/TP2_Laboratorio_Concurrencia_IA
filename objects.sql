-- =========================================================
-- objects.sql — Food Store
-- Vistas, función, triggers y procedimiento almacenado
-- Ejecutar después de schema.sql
-- =========================================================

-- ---------- Vistas obligatorias ----------

CREATE VIEW v_categorias_vigentes AS
SELECT id, nombre, descripcion
FROM categoria
WHERE eliminado = FALSE;

CREATE VIEW v_productos_vigentes AS
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE AND c.eliminado = FALSE;

CREATE VIEW v_pedidos_resumen AS
SELECT ped.id,
       u.nombre || ' ' || u.apellido AS usuario,
       ped.fecha, ped.estado, ped.forma_pago, ped.total
FROM pedido ped
JOIN usuario u ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE;

CREATE VIEW v_pedido_detalle AS
SELECT dp.pedido_id,
       pr.nombre AS producto,
       dp.cantidad, dp.precio_unitario, dp.subtotal
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
WHERE dp.eliminado = FALSE;

-- ---------- Función de cálculo de total (analogía con Calculable) ----------

CREATE OR REPLACE FUNCTION calcular_total_pedido(p_pedido_id BIGINT)
RETURNS NUMERIC(12,2) AS $$
    SELECT COALESCE(SUM(subtotal), 0)
    FROM detalle_pedido
    WHERE pedido_id = p_pedido_id AND eliminado = FALSE;
$$ LANGUAGE sql STABLE;

-- ---------- Trigger: subtotal y total automáticos ----------

-- Congela el precio y calcula subtotal antes de insertar/actualizar el detalle
CREATE OR REPLACE FUNCTION fn_set_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.precio_unitario IS NULL THEN
        SELECT precio INTO NEW.precio_unitario
        FROM producto WHERE id = NEW.producto_id;
    END IF;

    NEW.subtotal := NEW.cantidad * NEW.precio_unitario;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_subtotal
BEFORE INSERT OR UPDATE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_set_subtotal();

-- Recalcula el total del/los pedido(s) afectado(s), una sola pasada por sentencia
CREATE OR REPLACE FUNCTION fn_recalcular_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pedido p
    SET total = calcular_total_pedido(p.id)
    WHERE p.id IN (SELECT DISTINCT pedido_id FROM afectados);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Un trigger por evento: la transition table no admite varios eventos en un mismo CREATE TRIGGER
CREATE TRIGGER trg_total_ins
AFTER INSERT ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT EXECUTE FUNCTION fn_recalcular_total();

CREATE TRIGGER trg_total_upd
AFTER UPDATE ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT EXECUTE FUNCTION fn_recalcular_total();

-- ---------- Procedimiento transaccional (analogía con addDetallePedido + transacción) ----------

CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    p_usuario_id BIGINT,
    p_forma_pago forma_pago,
    p_items JSONB  -- [{"producto_id":1,"cantidad":2}, ...]
) AS $$
DECLARE
    v_pedido_id    BIGINT;
    v_item         JSONB;
    v_producto_id  BIGINT;
    v_cantidad     INTEGER;
    v_stock        INTEGER;
    v_disponible   BOOLEAN;
BEGIN
    -- El usuario debe existir y no estar eliminado
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id = p_usuario_id AND eliminado = FALSE) THEN
        RAISE EXCEPTION 'Usuario % inexistente o eliminado', p_usuario_id;
    END IF;

    INSERT INTO pedido(usuario_id, forma_pago)
    VALUES (p_usuario_id, p_forma_pago)
    RETURNING id INTO v_pedido_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_producto_id := (v_item->>'producto_id')::BIGINT;
        v_cantidad    := (v_item->>'cantidad')::INTEGER;

        -- Bloquea la fila del producto: evita sobreventa concurrente
        SELECT stock, disponible INTO v_stock, v_disponible
        FROM producto WHERE id = v_producto_id AND eliminado = FALSE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto % inexistente o eliminado', v_producto_id;
        END IF;

        IF NOT v_disponible THEN
            RAISE EXCEPTION 'Producto % no disponible', v_producto_id;
        END IF;

        IF v_stock < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente (producto %): hay %, se piden %',
                v_producto_id, v_stock, v_cantidad;
        END IF;

        INSERT INTO detalle_pedido(pedido_id, producto_id, cantidad)
        VALUES (v_pedido_id, v_producto_id, v_cantidad);

        -- Descuenta stock dentro de la misma transacción
        UPDATE producto SET stock = stock - v_cantidad WHERE id = v_producto_id;
    END LOOP;

    -- Si alguna inserción falla, toda la transacción se revierte (rollback).
END;
$$ LANGUAGE plpgsql;

-- Ejemplo de uso:
-- CALL sp_crear_pedido(
--     1, 'EFECTIVO',
--     '[{"producto_id":1,"cantidad":2}, {"producto_id":2,"cantidad":1}]'::jsonb
-- );
