-- =========================================================
-- transacciones.sql — Food Store
-- Escenarios de atomicidad, transacción manual, aislamiento
-- y concurrencia, pedidos por el DoD del TPI.
-- Ejecutar después de schema.sql, objects.sql y data.sql.
--
-- Los escenarios 1 y 2 corren con una sola sesión.
-- Los escenarios 3 y 4 requieren DOS sesiones psql simultáneas:
-- abrir dos terminales, cada una con `psql -d food_store`, y
-- alternar entre "SESIÓN 1" y "SESIÓN 2" en el orden indicado.
-- No hacer COMMIT/ROLLBACK hasta que el comentario lo indique.
-- =========================================================


-- =========================================================
-- 1) ATOMICIDAD — rollback automático en sp_crear_pedido
-- =========================================================

-- Antes: contar pedidos y detalles
SELECT count(*) AS pedidos_antes FROM pedido;
SELECT count(*) AS detalles_antes FROM detalle_pedido;

-- Ítem inválido: producto inexistente (id 9999)
CALL sp_crear_pedido(
    1, 'EFECTIVO',
    '[{"producto_id":1,"cantidad":2}, {"producto_id":9999,"cantidad":1}]'::jsonb
);
-- Se espera: ERROR:  Producto 9999 inexistente o eliminado

-- Después: mismos counts que antes → no quedó ni el pedido ni el primer detalle
SELECT count(*) AS pedidos_despues FROM pedido;
SELECT count(*) AS detalles_despues FROM detalle_pedido;


-- =========================================================
-- 2) TRANSACCIÓN MANUAL — COMMIT vs ROLLBACK
-- =========================================================

-- Secuencia A: con COMMIT (el cambio persiste)
BEGIN;
UPDATE producto SET stock = stock - 5 WHERE id = 1;
SELECT stock FROM producto WHERE id = 1;   -- ya ve el cambio, dentro de la misma transacción
COMMIT;
SELECT stock FROM producto WHERE id = 1;   -- sigue mostrando el cambio: quedó persistido

-- Secuencia B: con ROLLBACK (el cambio se descarta)
BEGIN;
UPDATE producto SET stock = stock - 5 WHERE id = 1;
SELECT stock FROM producto WHERE id = 1;   -- ve el cambio dentro de la transacción
ROLLBACK;
SELECT stock FROM producto WHERE id = 1;   -- vuelve al valor original: nunca se persistió


-- =========================================================
-- 3) AISLAMIENTO — READ COMMITTED vs SERIALIZABLE
-- Reproduce un lost update / lectura no repetible.
-- Requiere DOS sesiones simultáneas.
-- =========================================================

-- ---- Con READ COMMITTED (default de PostgreSQL) ----

-- SESIÓN 1:
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT stock FROM producto WHERE id = 1;   -- anotar el valor leído (ej. 10)
-- NO hacer COMMIT todavía: dejar la transacción abierta y pasar a la sesión 2

-- SESIÓN 2 (mientras la sesión 1 sigue abierta):
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE producto SET stock = stock - 3 WHERE id = 1;
COMMIT;

-- Volviendo a la SESIÓN 1:
UPDATE producto SET stock = stock - 4 WHERE id = 1;
SELECT stock FROM producto WHERE id = 1;   -- releyó el valor actual (post-commit de sesión 2) y restó 4
COMMIT;

-- ---- Repetir el mismo escenario con SERIALIZABLE ----
-- (recargar data.sql o restablecer el stock de producto id=1 antes de repetir)

-- SESIÓN 1:
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock FROM producto WHERE id = 1;
-- NO hacer COMMIT: pasar a la sesión 2

-- SESIÓN 2:
BEGIN ISOLATION LEVEL SERIALIZABLE;
UPDATE producto SET stock = stock - 3 WHERE id = 1;
COMMIT;

-- Volviendo a la SESIÓN 1:
UPDATE producto SET stock = stock - 4 WHERE id = 1;
COMMIT;
-- Se espera: ERROR:  could not serialize access due to concurrent update
-- PostgreSQL aborta la sesión 1 en vez de dejarla continuar con datos obsoletos.


-- =========================================================
-- 4) BLOQUEOS — SELECT ... FOR UPDATE evitando sobreventa
-- Requiere DOS sesiones simultáneas.
-- Usar un producto con stock bajo (ajustar el id / stock si hace falta,
-- ej.: UPDATE producto SET stock = 1 WHERE id = 5;)
-- =========================================================

-- SESIÓN 1:
BEGIN;
SELECT stock FROM producto WHERE id = 5 FOR UPDATE;  -- ej.: stock = 1 (última unidad)
-- Dejar la transacción abierta acá (sin COMMIT): la fila queda bloqueada

-- SESIÓN 2 (en simultáneo, mientras la sesión 1 sigue abierta):
BEGIN;
SELECT stock FROM producto WHERE id = 5 FOR UPDATE;
-- Esta sesión queda BLOQUEADA (esperando) hasta que la sesión 1 haga COMMIT/ROLLBACK

-- Volviendo a la SESIÓN 1:
UPDATE producto SET stock = stock - 1 WHERE id = 5;  -- vende la última unidad
COMMIT;

-- La SESIÓN 2 recién ahora se desbloquea y ve stock = 0:
-- su propia validación (IF v_stock < v_cantidad ...) debe rechazar la venta,
-- evitando la sobreventa de la misma unidad.
