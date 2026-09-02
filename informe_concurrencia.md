# Informe de Concurrencia — Parte 2

**Materia / TP:** Base de Datos II — TP2 Laboratorio Concurrencia IA, Parte 2
**Base involucrada:** `foodStore` (PostgreSQL 18.6) — se trabajó sobre `copia_trabajo`
**Fecha:** 2026-09-02
**Herramienta usada para las explicaciones:** OpenCode (asistente con IA)

> **Método (consigna §5.2):** cada escenario se ① reproduce con dos sesiones, ② se pide a la IA una explicación, ③ se verifica esa explicación en el motor real repitiendo el experimento con el nivel de aislamiento propuesto, y ④ se registra si la IA acertó. La explicación que vale es la que confirma el motor, no la que da el modelo.
>
> **Entorno:** dos sesiones psql (`Sesión A` y `Sesión B`) sobre `copia_trabajo`, sincronizadas con `pg_sleep()`. El código SQL completo de cada escenario está en `parte2_concurrencia.sql` y en los scripts de sesión usados.

---

## Escenario 1 — Lectura no repetible

| Campo | Contenido |
|---|---|
| **Escenario** | Lectura no repetible sobre `producto.stock` (fila id = 5, stock inicial 100). Con **Read Committed**, una misma consulta repetida dentro de la transacción cambia de resultado; repetir en **Repeatable Read** y mostrar que no cambia. |
| **Cómo se reprodujo** | **Sesión A** (primero): `BEGIN ISOLATION LEVEL READ COMMITTED; SELECT stock FROM producto WHERE id = 5;` → anota **100** y espera 6 s sin hacer COMMIT. **Sesión B** (a los ~3 s): `BEGIN ISOLATION LEVEL READ COMMITTED; UPDATE producto SET stock = stock - 30 WHERE id = 5; COMMIT;`. **Sesión A** repite `SELECT stock FROM producto WHERE id = 5;` dentro de la misma transacción y hace `ROLLBACK`. |
| **Qué se observó** | Salida real (Sesión A): `stock_primera_lectura = 100` → (B commitea) → `stock_segunda_lectura = 70`. **La misma consulta, en la misma transacción, devolvió 100 y después 70.** Salida real (Sesión B): `UPDATE 1`, `COMMIT`, `stock = 70`. |
| **Explicación de la IA** | «En Read Committed, PostgreSQL toma un nuevo snapshot **por cada sentencia**: la segunda `SELECT` de la Sesión A ve el `UPDATE` ya commiteado por la Sesión B, por eso el valor cambia dentro de la misma transacción. Para que la lectura sea repetible hay que subir el nivel a Repeatable Read, que toma **un único snapshot al inicio de la transacción** y lo mantiene hasta el `COMMIT`/`ROLLBACK`.» |
| **Verificación en el motor** | Se repitió exactamente el mismo experimento con `BEGIN ISOLATION LEVEL REPEATABLE READ` en la Sesión A. La Sesión B volvió a hacer `UPDATE producto SET stock = stock - 30 WHERE id = 5` y `COMMIT` (stock quedó en 70). La segunda `SELECT` de la Sesión A, repetida dentro de la misma transacción, devolvió **100** (el snapshot no cambió). Salida real: `stock_primera_lectura = 100` → `stock_segunda_lectura = 100`. |
| **Conclusión** | ✅ **La explicación de la IA se confirmó en el motor.** La lectura no repetible ocurre en Read Committed (100 → 70) y desaparece en Repeatable Read (100 → 100) porque el snapshot se toma una sola vez por transacción. **Nivel que resuelve el problema: REPEATABLE READ.** |

---

## Escenario 2 — Lectura fantasma

| Campo | Contenido |
|---|---|
| **Escenario** | Lectura fantasma sobre `categoria`. Un `COUNT` repetido dentro de la misma transacción cambia mientras otra sesión inserta una fila que cumple el `WHERE`. |
| **Cómo se reprodujo** | **Sesión A** (primero): `BEGIN ISOLATION LEVEL READ COMMITTED; SELECT COUNT(*) FROM categoria WHERE eliminado = FALSE;` → anota **4** y espera 6 s sin hacer COMMIT. **Sesión B** (a los ~3 s): `BEGIN; INSERT INTO categoria (nombre, descripcion) VALUES ('Combos', 'Combos y promociones'); COMMIT;`. **Sesión A** repite el `COUNT` dentro de la misma transacción y hace `ROLLBACK`. |
| **Qué se observó** | Salida real (Sesión A): `count_primero = 4` → (B inserta y commitea) → `count_segundo = 5`. **El `COUNT` aumentó de 4 a 5 dentro de la misma transacción**: apareció una fila "fantasma" que cumple la condición del `WHERE` (una categoría vigente nueva). Salida real (Sesión B): `INSERT 0 1`, `COMMIT`, id 5 = Combos. |
| **Explicación de la IA** | «En Read Committed, el `COUNT` es una sentencia independiente que ve el estado de la base al momento de ejecutarse; por eso ve el `INSERT` ya commiteado por la Sesión B. La fila nueva que cumple el `WHERE` es una "lectura fantasma" según la definición del estándar. Con Repeatable Read el `COUNT` usa el snapshot único de la transacción, así que no ve el `INSERT` de B y el resultado repetido no cambia.» |
| **Verificación en el motor** | Se repitió el experimento con `BEGIN ISOLATION LEVEL REPEATABLE READ` en la Sesión A. La Sesión B volvió a insertar `Combos` y commiteó. El segundo `COUNT` de la Sesión A, repetido dentro de la misma transacción, devolvió **4** (el snapshot no incluye el INSERT de B). Salida real: `count_primero = 4` → `count_segundo = 4`. (La fila `Combos` insertada por B se eliminó después para dejar la copia limpia.) |
| **Conclusión** | ✅ **La explicación de la IA se confirmó en el motor.** La lectura fantasma ocurre en Read Committed (4 → 5) y desaparece en Repeatable Read (4 → 4). **Nivel que resuelve el problema: REPEATABLE READ** (snapshot único; en la definición estricta de la norma, para la anomalía de filosofía se necesitaría Serializable, pero para este caso el snapshot alcanza). |

---

## Escenario 3 — Espera por bloqueo

| Campo | Contenido |
|---|---|
| **Escenario** | Espera por bloqueo con `SELECT ... FOR UPDATE` sobre la misma fila de `pedido` (id = 1). La segunda sesión queda esperando hasta que la primera hace `COMMIT`/`ROLLBACK`. |
| **Cómo se reprodujo** | **Sesión A** (primero): `BEGIN; SELECT id, estado FROM pedido WHERE id = 1 FOR UPDATE;` → toma el lock y lo mantiene 12 s. **Sesión B** (a los ~2 s): `BEGIN; SELECT id, estado FROM pedido WHERE id = 1 FOR UPDATE;` → **queda esperando** (bloqueada). **Sesión A**: `COMMIT;` → libera el lock → **Sesión B** se desbloquea y devuelve la fila. `ROLLBACK;` en B. |
| **Qué se observó** | Mientras B estaba esperando, se consultó `pg_stat_activity` y mostró **la prueba del bloqueo** (salida real): una sesión con `state = active`, `wait_event_type = Lock`, `wait_event = transactionid` y query `SELECT id, estado FROM pedido WHERE id = 1 FOR UPDATE;` (la Sesión B esperando el lock), y la otra sesión en `pg_sleep(12)` (la Sesión A reteniendo el lock). Al hacer `COMMIT` en A, la Sesión B devolvió `id=1, estado=CONFIRMADO` inmediatamente. |
| **Explicación de la IA** | «`SELECT ... FOR UPDATE` toma un lock **exclusivo** sobre la fila. Mientras la Sesión A no haga `COMMIT` o `ROLLBACK`, la Sesión B no puede tomar ese mismo lock y queda en espera (bloqueada). Es el mecanismo que evita la sobreventa: quien lee "para actualizar" bloquea la fila para que otra sesión no la modifique a mitad de camino. El lock se libera al terminar la transacción.» |
| **Verificación en el motor** | Se repitió y se confirmó en `pg_stat_activity`: la Sesión B figuraba con `wait_event_type = Lock` esperando el `transactionid` de la Sesión A, y se desbloqueó recién después del `COMMIT` de A. El comportamiento esperado (espera → liberación → lectura) se observó en ambas corridas. |
| **Conclusión** | ✅ **La explicación de la IA se confirmó en el motor.** El **`SELECT ... FOR UPDATE`** es el mecanismo de bloqueo que serializa el acceso a la fila; sin él, las dos sesiones podrían leer el mismo valor y después actualizar una sobre la otra (pérdida de actualización). |

---

## Escenario 4 — Interbloqueo real (opcional, nota adicional)

| Campo | Contenido |
|---|---|
| **Escenario** | Interbloqueo (deadlock) con `UPDATE` en orden cruzado sobre `producto` (filas 1 y 2). El motor aborta una sesión con el error **40P01**. |
| **Cómo se reprodujo** | **Sesión A** (primero): `BEGIN; UPDATE producto SET stock = stock - 1 WHERE id = 1;` (toma fila 1), espera 4 s. **Sesión B** (a los ~1 s): `BEGIN; UPDATE producto SET stock = stock - 1 WHERE id = 2;` (toma fila 2), espera 2 s. **Sesión A** intenta `UPDATE producto SET stock = stock - 1 WHERE id = 2;` (espera a B). **Sesión B** intenta `UPDATE producto SET stock = stock - 1 WHERE id = 1;` (espera a A) → **ciclo de espera** → el motor detecta el deadlock y aborta una sesión. |
| **Qué se observó** | Salida real — el motor abortó a la **Sesión A**: `ERROR: se ha detectado un deadlock`. `DETALLE: El proceso 8440 espera ShareLock en transacción 781; bloqueado por proceso 9060. El proceso 9060 espera ShareLock en transacción 780; bloqueado por proceso 8440.` (código SQL **40P01**). La **Sesión B** sobrevivió: su segundo `UPDATE` devolvió `UPDATE 1` y pudo hacer `COMMIT` sin error. |
| **Explicación de la IA** | «Es un interbloqueo: dos sesiones tienen cada una un lock de fila que la otra necesita, formando un ciclo de espera (A espera la fila 2 que tiene B; B espera la fila 1 que tiene A). PostgreSQL lo detecta con su detector de deadlock y aborta a una de las sesiones (normalmente la que detecta en el ciclo) para romperlo, permitiendo que la otra avance. La sesión abortada recibe el error 40P01 y su transacción queda en estado aborted, lista para `ROLLBACK`.» |
| **Verificación en el motor** | Se reprodujo y se confirmó el error **40P01** (`ERROR: se ha detectado un deadlock` + DETALLE con el ciclo de esperas ShareLock). La sesión sobreviviente pudo completar su transacción. El `DETALLE` del motor mostró exactamente el ciclo descrito por la IA. |
| **Conclusión** | ✅ **La explicación de la IA se confirmó en el motor.** El interbloqueo se produce por locks en **orden cruzado**, y lo resuelve el **detector de deadlock** de PostgreSQL abortando una sesión con el error 40P01. |

---

## Resumen y conclusión general

Se reprodujeron y verificaron en el motor real **4 escenarios** (3 obligatorios + el interbloqueo opcional):

| # | Escenario | Nivel/mecanismo que lo evita | ¿Confirmada la IA? |
|---|---|---|---|
| 1 | Lectura no repetible | **REPEATABLE READ** (100→70 vs 100→100) | ✅ Sí |
| 2 | Lectura fantasma | **REPEATABLE READ** (4→5 vs 4→4) | ✅ Sí |
| 3 | Espera por bloqueo | **FOR UPDATE** (lock de fila, evidencia en `pg_stat_activity`) | ✅ Sí |
| 4 | Interbloqueo (opcional) | **Detector de deadlock** del motor (aborta con 40P01) | ✅ Sí |

**Conclusión general:** las cuatro explicaciones generadas por la IA se confirmaron empíricamente en PostgreSQL 18. El nivel de aislamiento **Repeatable Read** elimina la lectura no repetible y la lectura fantasma en este esquema manteniendo un snapshot por transacción; el bloqueo explícito **`SELECT ... FOR UPDATE`** serializa la actualización de una fila y evita la sobreventa; y el **detector de deadlock** del motor resuelve los ciclos de espera abortando a una sesión con el error 40P01. Todo el trabajo se hizo sobre `copia_trabajo` siguiendo el protocolo de la Parte 0 (copia, transacción y verificación), y la copia quedó restaurada a su estado original al final.

---

*Firma del estudiante: Ivana Gutierrez*