-- =========================================================
-- queries.sql — Food Store
-- Una consulta resuelta y comentada por cada historia de usuario
-- del anexo, más las consultas analíticas adicionales.
-- Ejecutar después de schema.sql, objects.sql y data.sql.
-- Ajustar los literales (ids, nombres, mails) a los datos reales.
-- =========================================================

-- =========================================================
-- ÉPICA 1 — Gestión de Categorías
-- =========================================================

-- HU-CAT-01 — Listar categorías vigentes
SELECT id, nombre, descripcion
FROM categoria
WHERE eliminado = FALSE
ORDER BY id;

-- HU-CAT-02 — Crear categoría
INSERT INTO categoria(nombre, descripcion)
VALUES ('Combos', 'Combos y promociones')
RETURNING id;

-- HU-CAT-03 — Editar categoría
UPDATE categoria
SET nombre = 'Pizzas y Empanadas', descripcion = 'Catálogo ampliado'
WHERE id = 1 AND eliminado = FALSE; -- 0 filas si no existe/eliminada

-- HU-CAT-04 — Eliminar categoría (baja lógica)
-- Decisión de diseño: se impide la baja si la categoría tiene productos vigentes
-- (alternativa: permitirla y dejar los productos "huérfanos" de una categoría eliminada).
UPDATE categoria
SET eliminado = TRUE
WHERE id = 2 AND eliminado = FALSE
  AND NOT EXISTS (
      SELECT 1 FROM producto WHERE categoria_id = 2 AND eliminado = FALSE
  );

-- =========================================================
-- ÉPICA 2 — Gestión de Productos
-- =========================================================

-- HU-PROD-01 — Listar productos vigentes (con filtro opcional por categoría)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
-- AND p.categoria_id = 1 -- filtro opcional
ORDER BY p.id;

-- HU-PROD-02 — Crear producto (valida categoría existente y vigente)
INSERT INTO producto(nombre, descripcion, precio, stock, imagen, disponible, categoria_id)
SELECT 'Calabresa', 'Pizza de longaniza calabresa', 3600.00, 12, NULL, TRUE, c.id
FROM categoria c
WHERE c.id = 1 AND c.eliminado = FALSE -- garantiza categoría vigente
RETURNING id;

-- HU-PROD-03 — Editar producto (UPDATE parcial: NULL conserva el valor actual)
UPDATE producto
SET precio = COALESCE(2000.00, precio),
    stock  = COALESCE(NULL, stock)
WHERE id = 1 AND eliminado = FALSE;

-- HU-PROD-04 — Eliminar producto (baja lógica)
UPDATE producto
SET eliminado = TRUE
WHERE id = 1 AND eliminado = FALSE;

-- =========================================================
-- ÉPICA 3 — Gestión de Usuarios
-- =========================================================

-- HU-USR-01 — Listar usuarios vigentes
SELECT id, nombre, apellido, mail, rol
FROM usuario
WHERE eliminado = FALSE
ORDER BY id;

-- HU-USR-02 — Crear usuario (mail único; en producción "contrasena" debe ser un hash, nunca texto plano)
INSERT INTO usuario(nombre, apellido, mail, celular, contrasena)
VALUES ('Sofía', 'Ramos', 'sofia@x.com', '2615551234', 'hash_sofia')
RETURNING id; -- UNIQUE(mail) lanza error si el mail ya existe

-- HU-USR-03 — Editar usuario
UPDATE usuario
SET celular = '2617654321'
WHERE id = 2 AND eliminado = FALSE;

-- HU-USR-04 — Eliminar usuario (baja lógica)
UPDATE usuario
SET eliminado = TRUE
WHERE id = 5 AND eliminado = FALSE;

-- =========================================================
-- ÉPICA 4 — Gestión de Pedidos y Detalles
-- =========================================================

-- HU-PED-01 — Listar pedidos (con filtro opcional por usuario)
SELECT id, usuario, fecha, estado, forma_pago, total
FROM v_pedidos_resumen
-- WHERE usuario = 'Ana Garis' -- filtro opcional
ORDER BY id;

-- HU-PED-02 — Crear pedido con detalles (usuario_id, forma_pago, items JSON)
CALL sp_crear_pedido(
    2, -- usuario_id (debe estar vigente)
    'EFECTIVO',
    '[{"producto_id":1,"cantidad":2},
      {"producto_id":2,"cantidad":1}]'::jsonb);

-- HU-PED-03 — Actualizar estado / forma de pago
UPDATE pedido
SET estado = 'CONFIRMADO', forma_pago = 'TARJETA'
WHERE id = 1 AND eliminado = FALSE;

-- HU-PED-04 — Eliminar pedido (baja lógica, en cascada sobre sus detalles)
BEGIN;
UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 1;
UPDATE pedido SET eliminado = TRUE WHERE id = 1;
COMMIT;

-- =========================================================
-- Consultas analíticas adicionales
-- Todas filtran por eliminado = FALSE para respetar el borrado lógico.
-- =========================================================

-- A) Top 5 productos más vendidos (por cantidad)
SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
WHERE dp.eliminado = FALSE
GROUP BY pr.id, pr.nombre
ORDER BY unidades DESC
LIMIT 5;

-- B) Facturación total por categoría y por mes
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha) AS mes,
       SUM(dp.subtotal) AS facturado
FROM detalle_pedido dp
JOIN pedido ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
WHERE dp.eliminado = FALSE
GROUP BY c.nombre, date_trunc('month', ped.fecha)
ORDER BY mes, facturado DESC;

-- C) Ranking de usuarios por gasto acumulado (función de ventana)
SELECT u.id, u.nombre || ' ' || u.apellido AS usuario,
       SUM(ped.total) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM pedido ped
JOIN usuario u ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE
GROUP BY u.id, u.nombre, u.apellido
ORDER BY puesto;

-- D) Pedidos cuyo total supera el promedio general (subconsulta correlacionada)
SELECT id, total
FROM pedido
WHERE eliminado = FALSE
  AND total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
ORDER BY total DESC;

-- E) Productos sin ventas (LEFT JOIN + IS NULL)
SELECT pr.id, pr.nombre
FROM producto pr
LEFT JOIN detalle_pedido dp
       ON dp.producto_id = pr.id AND dp.eliminado = FALSE
WHERE pr.eliminado = FALSE
  AND dp.id IS NULL
ORDER BY pr.id;
