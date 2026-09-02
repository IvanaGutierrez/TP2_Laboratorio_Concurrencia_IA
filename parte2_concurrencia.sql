-- =========================================================
-- parte2_concurrencia.sql — Food Store
-- Escenarios de concurrencia para el informe de la Parte 2 del TP.
--
-- Requiere DOS sesiones psql simultáneas sobre copia_trabajo.
-- Abrir dos terminales, cada una con:
--   psql -U postgres -d copia_trabajo
-- y alternar entre "SESIÓN A" y "SESIÓN B" en el orden indicado.
-- NO hacer COMMIT/ROLLBACK hasta que el comentario de la sesión lo diga.
-- =========================================================


-- =========================================================
-- ESCENARIO 1 — LECTURA NO REPETIBLE (Read Committed vs Repeatable Read)
-- Tabla: producto (stock)
-- =========================================================

-- ---- 1.a) READ COMMITTED (default de PostgreSQL): SÍ cambia ----

-- SESIÓN A:
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT stock FROM producto WHERE id = 5;
-- anotar el valor (ej. 100). NO hacer COMMIT todavía: pasar a Sesión B.

-- SESIÓN B:
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE producto SET stock = stock - 30 WHERE id = 5;
COMMIT;

-- Volviendo a SESIÓN A: repetir la misma consulta DENTRO de la misma transacción
SELECT stock FROM producto WHERE id = 5;
-- la segunda lectura ve 70 (cambió respecto de la primera, que vio 100):
-- comportamiento de READ COMMITTED.
ROLLBACK;

-- ---- 1.b) REPEATABLE READ: NO cambia ----
-- (restaurar primero el stock de producto 5 al valor original, ej. 100)

-- SESIÓN A:
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT stock FROM producto WHERE id = 5;
-- anotar (ej. 100). NO hacer COMMIT todavía.

-- SESIÓN B:
BEGIN;
UPDATE producto SET stock = stock - 30 WHERE id = 5;
COMMIT;

-- Volviendo a SESIÓN A: la misma consulta sigue devolviendo 100
SELECT stock FROM producto WHERE id = 5;
-- el snapshot de REPEATABLE READ no cambia aunque otra sesión haya commiteado
-- => la lectura si es repetible.
ROLLBACK;


-- =========================================================
-- ESCENARIO 2 — LECTURA FANTASMA (COUNT que cambia)
-- Tabla: categoria (INSERT de una fila que cumple el WHERE)
-- =========================================================

-- SESIÓN A:
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT COUNT(*) FROM categoria WHERE eliminado = FALSE;
-- anotar (ej. 4). NO hacer COMMIT todavía.

-- SESIÓN B:
BEGIN;
INSERT INTO categoria (nombre, descripcion) VALUES ('Combos', 'Combos y promociones');
COMMIT;

-- Volviendo a SESIÓN A: repetir el COUNT dentro de la misma transacción
SELECT COUNT(*) FROM categoria WHERE eliminado = FALSE;
-- ahora da 5: apareció una fila "fantasma" que cumple la condición del WHERE.
-- En READ COMMITTED esto se ve. En REPEATABLE READ el COUNT repetido da 4 (no cambia).
ROLLBACK;


-- =========================================================
-- ESCENARIO 3 — ESPERA POR BLOQUEO (SELECT ... FOR UPDATE)
-- Tabla: pedido (fila id = 1)
-- =========================================================

-- SESIÓN A:
BEGIN;
SELECT id, estado FROM pedido WHERE id = 1 FOR UPDATE;
-- la fila 1 queda bloqueada. NO hacer COMMIT todavía: pasar a Sesión B.

-- SESIÓN B (mientras A sigue abierta):
BEGIN;
SELECT id, estado FROM pedido WHERE id = 1 FOR UPDATE;
-- esta sentencia queda ESPERANDO (bloqueada) hasta que la Sesión A
-- haga COMMIT/ROLLBACK. (En DBeaver/psql parece que "no devuelve".)
-- NO hacer nada todavía; volver a la Sesión A.

-- SESIÓN A: liberar el bloqueo
COMMIT;

-- La SESIÓN B recién ahora se desbloquea y devuelve la fila 1.
ROLLBACK;


-- =========================================================
-- ESCENARIO 4 — INTERBLOQUEO REAL (opcional, error 40P01)
-- Tabla: producto (filas 1 y 2, bloqueadas en orden cruzado)
-- =========================================================

-- SESIÓN A:
BEGIN;
UPDATE producto SET stock = stock - 1 WHERE id = 1;   -- toma fila 1
-- NO hacer COMMIT. Pasar a Sesión B.

-- SESIÓN B:
BEGIN;
UPDATE producto SET stock = stock - 1 WHERE id = 2;   -- toma fila 2
-- NO hacer COMMIT. Volver a Sesión A.

-- SESIÓN A: pide la fila que tiene B (queda esperando)
UPDATE producto SET stock = stock - 1 WHERE id = 2;
-- NO hacer nada. Volver a Sesión B.

-- SESIÓN B: pide la fila que tiene A => el motor detecta el ciclo
UPDATE producto SET stock = stock - 1 WHERE id = 1;
-- Se espera: ERROR: deadlock detected ... SQL state 40P01
-- PostgreSQL aborta la Sesión B (u A). La sobreviviente puede COMMIT/ROLLBACK.
ROLLBACK;  -- en la sesión que quedó viva
-- =========================================================

-- NOTA: todos estos escenarios terminan en ROLLBACK; sobre copia_trabajo
-- no persiste ningún cambio. Verificar resultados en informe_concurrencia.md.
