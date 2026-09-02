# Declaración de Uso de IA (DUIA) — Parte 2: Informe de Concurrencia

**Materia / TP:** Base de Datos II — TP2 Laboratorio Concurrencia IA, Parte 2
**Base involucrada:** `foodStore` (PostgreSQL 18.6) — se trabajó sobre `copia_trabajo`
**Fecha:** 2026-09-02

---

## Herramienta

OpenCode (asistente de código con IA). Sesión de reproducción de escenarios de concurrencia y redacción del informe.

## Spec o prompt utilizado

Resumen del prompt dado al asistente:

> "Resolver la Parte 2 del TP: reproducir con dos sesiones concurrentes sobre las tablas del proyecto al menos tres anomalías de concurrencia (lectura no repetible sobre `producto.stock`, lectura fantasma sobre `categoria`, espera por bloqueo con `SELECT ... FOR UPDATE` sobre `pedido`, y opcional interbloqueo sobre `producto`). Para cada escenario: dar los comandos exactos de Sesión A y Sesión B en orden, capturar la salida real del motor, pedir una explicación, verificar esa explicación en el motor repitiendo el experimento con el nivel de aislamiento propuesto, y registrar si la IA acertó. Armar `informe_concurrencia.md` con la estructura de la consigna §5.3."

## Qué generó

- **Script `parte2_concurrencia.sql`:** los 4 escenarios (los 3 obligatorios + el interbloqueo opcional) con los comandos de Sesión A y Sesión B comentados y en orden, listos para correr en dos sesiones psql.
- **Scripts de sesión temporales (por escenario y por nivel):** versiones con `pg_sleep()` para sincronizar las dos sesiones y capturar la salida real de cada una (esc1_sesionA/B, esc1b, esc2, esc2b, esc3, esc3b con verificación de `pg_stat_activity`, esc4).
- **Informe `informe_concurrencia.md`:** estructura completa de la consigna §5.3 con los 4 escenarios, las salidas reales del motor y las conclusiones.

## Qué se aceptó

- El **diseño de los escenarios** (tablas, filas, comandos y orden entre sesiones) tal como lo propuso la IA: `producto.id=5` (stock 100) para lectura no repetible, `categoria` (4 filas) para lectura fantasma, `pedido.id=1` para espera por bloqueo, `producto.id=1,2` para el interbloqueo.
- Las **explicaciones** de la IA se incluyeron en el informe tal cual se dieron, y luego se marcó en cada una si el motor la confirmó o no (todas se confirmaron).
- La **verificación en el motor** (repetición del experimento con `REPEATABLE READ` para los escenarios 1 y 2) se aceptó porque la salida real coincidió con lo esperado.

## Qué se modificó o descartó, y por qué

- **Sincronización con `pg_sleep()`:** en una primera corrida la Sesión B arrancó antes que la A y el escenario no mostró el fenómeno (la primera lectura de A ya veía el valor cambiado). Se corrigió invirtiendo el orden de lanzamiento (A primero, B con retraso) para que A tomara su snapshot/lectura inicial antes del UPDATE/INSERT de B. Es un ajuste técnico de ejecución, no del fenómeno.
- **Segunda corrida del Escenario 3 con `pg_stat_activity`:** se agregó la verificación de que la sesión B figuraba con `wait_event_type = Lock` mientras esperaba, para que el informe muestre la evidencia del bloqueo y no solo el orden de los comandos.
- **Restauración de la copia:** después de cada escenario se devolvieron los valores originales a la copia (stock de productos 1, 2 y 5; borrado de la categoría 'Combos' insertada en el escenario 2) para que cada corrida partiera del mismo estado del seed. No se alteró `foodStore` en ningún momento.

## Verificación realizada

- **Escenario 1 (lectura no repetible):** con `READ COMMITTED`, la misma `SELECT` en la misma transacción devolvió `100` y luego `70` (el UPDATE commiteado de B) → fenómeno reproducido. Con `REPEATABLE READ`, devolvió `100` y `100` → verificado que el nivel lo evita.
- **Escenario 2 (lectura fantasma):** con `READ COMMITTED`, el `COUNT(*)` devolvió `4` y luego `5` → fenómeno reproducido. Con `REPEATABLE READ`, devolvió `4` y `4` → verificado que el nivel lo evita.
- **Escenario 3 (espera por bloqueo):** la Sesión B quedó esperando el lock de `pedido.id=1` (confirmado con `pg_stat_activity`: `wait_event_type=Lock`, `wait_event=transactionid`) y se desbloqueó tras el `COMMIT` de A.
- **Escenario 4 (interbloqueo):** el motor abortó a la Sesión A con `ERROR: se ha detectado un deadlock` (40P01) y el `DETALLE` mostró el ciclo de esperas; la Sesión B sobrevivió y commiteó.
- **Estado final:** la copia de trabajo quedó restaurada a los valores del seed (stocks 20/15/100, 4 categorías) y `foodStore` nunca se modificó (solo se usó como template para crear la copia).

---

*Firma del estudiante: Ivana Gutierrez*