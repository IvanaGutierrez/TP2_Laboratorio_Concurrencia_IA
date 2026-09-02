-- =========================================================
-- data.sql — Food Store (datos de ejemplo / seed)
-- Ejecutar después de schema.sql y objects.sql
-- Asume base vacía: los IDs autonuméricos empiezan en 1
-- =========================================================

-- ---------- Categorías ----------
INSERT INTO categoria (nombre, descripcion) VALUES
    ('Pizzas',     'Pizzas al molde y a la piedra'),
    ('Empanadas',  'Empanadas fritas y al horno'),
    ('Bebidas',    'Gaseosas, aguas y cervezas'),
    ('Postres',    'Postres y dulces caseros');
-- id: 1 Pizzas, 2 Empanadas, 3 Bebidas, 4 Postres

-- ---------- Productos ----------
-- Productos 11 y 12 quedan sin ventas a propósito (para HU de "productos sin ventas")
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES
    ('Muzzarella',        'Pizza clásica de muzzarella',      3200.00, 20, TRUE,  1),  -- 1
    ('Fugazzeta',         'Pizza de cebolla',                 3500.00, 15, TRUE,  1),  -- 2
    ('Napolitana',        'Pizza con tomate y ajo',           3800.00, 10, TRUE,  1),  -- 3
    ('Carne',             'Empanada de carne cortada a cuchillo', 350.00, 100, TRUE, 2),  -- 4
    ('Jamón y queso',     'Empanada de jamón y queso',         350.00, 100, TRUE,  2),  -- 5
    ('Humita',            'Empanada de humita',                350.00,  80, TRUE,  2),  -- 6
    ('Coca-Cola 500ml',   'Gaseosa línea Coca-Cola',            900.00,  50, TRUE,  3),  -- 7
    ('Agua mineral',      'Agua sin gas 500ml',                 700.00,  60, TRUE,  3),  -- 8
    ('Cerveza artesanal', 'IPA local 473ml',                   1500.00,  30, TRUE,  3),  -- 9
    ('Flan casero',       'Flan con dulce de leche',           1200.00,  25, TRUE,  4),  -- 10
    ('Helado 1/4kg',      'Pote de helado artesanal',          2000.00,   0, FALSE, 4),  -- 11 (sin stock, sin ventas)
    ('Tiramisú',          'Porción individual',                2200.00,  15, TRUE,  4);  -- 12 (sin ventas)

-- ---------- Usuarios ----------
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES
    ('Ana',    'Garis',      'ana@foodstore.com',   '2610000001', 'hash_admin', 'ADMIN'),    -- 1
    ('Juan',   'Pérez',      'juan@x.com',          '2611234567', 'hash_juan',  'USUARIO'),  -- 2
    ('María',  'López',      'maria@x.com',         '2612345678', 'hash_maria', 'USUARIO'),  -- 3
    ('Carlos', 'Díaz',       'carlos@x.com',        '2613456789', 'hash_carlos','USUARIO'),  -- 4
    ('Lucía',  'Fernández',  'lucia@x.com',         '2614567890', 'hash_lucia', 'USUARIO');  -- 5

-- ---------- Pedidos ----------
-- Repartidos en 3 meses distintos (jun/jul/ago) y entre varios usuarios,
-- para poder probar facturación por mes, ranking por usuario y promedio general.
-- fecha, forma_pago y usuario_id se fijan explícitamente; total lo calcula el trigger.
INSERT INTO pedido (fecha, estado, forma_pago, usuario_id) VALUES
    ('2026-06-05', 'CONFIRMADO', 'EFECTIVO',      2),  -- pedido 1
    ('2026-06-12', 'TERMINADO',  'TARJETA',       3),  -- pedido 2
    ('2026-06-20', 'TERMINADO',  'TRANSFERENCIA', 2),  -- pedido 3
    ('2026-07-02', 'TERMINADO',  'EFECTIVO',      4),  -- pedido 4
    ('2026-07-10', 'CANCELADO',  'TARJETA',       5),  -- pedido 5
    ('2026-07-18', 'TERMINADO',  'EFECTIVO',      3),  -- pedido 6
    ('2026-07-25', 'TERMINADO',  'TARJETA',       2),  -- pedido 7
    ('2026-08-03', 'CONFIRMADO', 'EFECTIVO',      4),  -- pedido 8
    ('2026-08-11', 'TERMINADO',  'TRANSFERENCIA', 5),  -- pedido 9
    ('2026-08-19', 'TERMINADO',  'TARJETA',       3);  -- pedido 10

-- ---------- Detalles de pedido ----------
-- No se especifica precio_unitario: el trigger trg_subtotal lo congela
-- con producto.precio vigente y calcula subtotal automáticamente.
-- Los triggers trg_total_ins recalculan pedido.total al vuelo.
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES
    -- Pedido 1 (Juan, junio)
    (1, 1, 2), (1, 7, 3),
    -- Pedido 2 (María, junio)
    (2, 2, 1), (2, 4, 5),
    -- Pedido 3 (Juan, junio)
    (3, 3, 1),
    -- Pedido 4 (Carlos, julio)
    (4, 1, 3), (4, 9, 2),
    -- Pedido 5 (Lucía, julio — CANCELADO, igual queda el detalle para historial)
    (5, 2, 2),
    -- Pedido 6 (María, julio)
    (6, 5, 10), (6, 8, 4),
    -- Pedido 7 (Juan, julio)
    (7, 1, 1), (7, 3, 1), (7, 10, 2),
    -- Pedido 8 (Carlos, agosto)
    (8, 6, 8),
    -- Pedido 9 (Lucía, agosto)
    (9, 2, 4), (9, 9, 1),
    -- Pedido 10 (María, agosto)
    (10, 1, 5), (10, 7, 5), (10, 10, 3);

-- ---------- Verificación rápida post-carga ----------
-- SELECT id, total FROM pedido ORDER BY id;              -- debería mostrar totales != 0
-- SELECT * FROM v_pedido_detalle WHERE pedido_id = 1;    -- debería mostrar 2 líneas
-- SELECT pr.nombre FROM producto pr
--   LEFT JOIN detalle_pedido dp ON dp.producto_id = pr.id
--   WHERE dp.id IS NULL;                                  -- debería devolver Helado y Tiramisú
