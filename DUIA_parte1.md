# Declaración de Uso de IA (DUIA) — Parte 1: Restricciones de Integridad

**Materia / TP:** Base de Datos — TP2 Laboratorio Concurrencia IA, Parte 1
**Base involucrada:** `food_store` (PostgreSQL) — se trabaja sobre `copia_trabajo`
**Fecha:** 2026-09-01

---

## Herramienta

OpenCode (asistente de código con IA). Sesión de generación de restricciones de integridad.

## Spec o prompt utilizado

Resumen del prompt dado al asistente:

> "Resolver la Parte 1 del TP: generar restricciones de integridad para reglas de negocio que hoy dependen de la aplicación y no están garantizadas por el motor. Analizar el esquema completo (`producto`, `pedido`, `detalle_pedido`, `categoria`, `usuario`) y detectar 2 o 3 reglas no cubiertas por los CHECK/UNIQUE/FK existentes, priorizando: (a) que `pedido.estado` no pueda retroceder de un estado avanzado a uno anterior; (b) que `detalle_pedido.subtotal` sea siempre `cantidad * precio_unitario`; (c) cualquier otra regla real detectada. Para cada regla: escribir la spec con tabla y columna exactas, proponer CHECK o trigger (trigger si compara valor viejo vs nuevo), y generar un archivo `restricciones_integridad.sql` con los scripts y 2 pruebas por regla (una que debe fallar, una que debe pasar). No aplicar nada sobre la base real."

## Qué generó

- **Regla 1 — `pedido.estado` (transiciones sin retroceso):** trigger `trg_validar_estado` + función `fn_validar_transicion_estado()`. Secuencia válida PENDIENTE → CONFIRMADO → TERMINADO; CANCELADO terminal (solo desde PENDIENTE o CONFIRMADO); TERMINADO/CANCELADO no cambian de estado.
- **Regla 2 — `detalle_pedido` (bloqueo de líneas en pedido cerrado):** trigger `trg_bloquear_detalle_cerrado` + función `fn_bloquear_detalle_pedido_cerrado()`. No permite INSERT/UPDATE de detalles en pedidos CONFIRMADO, TERMINADO o CANCELADO; solo PENDIENTE.
- **Archivo `restricciones_integridad.sql`:** scripts re-ejecutables (`DROP ... IF EXISTS` + creación) con spec y justificación comentadas por regla.
- **Archivo `restricciones_integridad_test.sql`:** empaqueta las restricciones + las 4 pruebas (1A, 1B, 2A, 2B) dentro de `BEGIN; ... ROLLBACK;`, con SAVEPOINT en las pruebas que deben fallar y comentarios del resultado esperado de cada una.
- **4 pruebas:** 1A (falla: retroceso CONFIRMADO → PENDIENTE), 1B (pasa: avance CONFIRMADO → TERMINADO), 2A (falla: insertar detalle en pedido CONFIRMADO), 2B (pasa: insertar detalle en pedido PENDIENTE).

## Qué se aceptó

Se aceptaron las 2 reglas propuestas y su implementación, tal como quedaron en `restricciones_integridad.sql` / `aplicar_restricciones.sql`, después de que las 4 pruebas dieron el resultado esperado sobre `copia_trabajo` el 2026-09-02:

- **Regla 1** (`trg_validar_estado` + `fn_validar_transicion_estado`): aceptada tal cual la generó la IA. La prueba 1A falló con el error esperado y la 1B pasó.
- **Regla 2** (`trg_bloquear_detalle_cerrado` + `fn_bloquear_detalle_pedido_cerrado`): aceptada tal cual la generó la IA. La prueba 2A falló con el error esperado y la 2B pasó.
- Los triggers quedaron instalados en `copia_trabajo` (verificados en `pg_trigger`: `trg_validar_estado` sobre `pedido`, `trg_bloquear_detalle_cerrado` sobre `detalle_pedido`) junto con los triggers preexistentes de `objects.sql`.

## Qué se modificó o descartó, y por qué

- **Descartada la regla `detalle_pedido.subtotal = cantidad * precio_unitario`:** ya estaba garantizada por el trigger existente `trg_subtotal` (definido en `objects.sql`, que congela `precio_unitario` desde `producto.precio` y calcula `subtotal` automáticamente). Inferirla de nuevo habría sido duplicación.
- **No incluida una 3.ª regla opcional "todo pedido debe tener al menos un detalle":** es una regla real (hoy nada lo impide si se inserta `pedido` a mano), pero una implementación robusta requiere control sobre el DELETE del último detalle y choca parcialmente con el patrón de soft-delete del proyecto. Se dejó documentada como candidata, no como restricción aplicada.
- **Forma de implementación:** se eligieron triggers (no CHECK) para ambas reglas porque necesitan comparar el valor viejo con el nuevo (Regla 1) o consultar el estado del pedido padre (Regla 2); un CHECK no puede evaluar esas condiciones.

## Verificación realizada

Ejecución real sobre `copia_trabajo` (2026-09-02) con `restricciones_integridad_test.sql` (todo dentro de `BEGIN; ... ROLLBACK;` por protocolo; las pruebas que deben fallar están protegidas con SAVEPOINT):

Salida real del motor:

```
BEGIN
DROP FUNCTION
CREATE FUNCTION
DROP TRIGGER
CREATE TRIGGER
DROP FUNCTION
CREATE FUNCTION
DROP TRIGGER
CREATE TRIGGER
SAVEPOINT
ROLLBACK
ERROR:  Transición inválida: CONFIRMADO → PENDIENTE (solo se permite → TERMINADO o → CANCELADO)
CONTEXTO:  función PL/pgSQL fn_validar_transicion_estado() en la línea 20 en RAISE
ERROR:  No se pueden modificar detalles de un pedido en estado CONFIRMADO (pedido 1)
CONTEXTO:  función PL/pgSQL fn_bloquear_detalle_pedido_cerrado() en la línea 10 en RAISE
UPDATE 1
SAVEPOINT
ROLLBACK
 id
----
 11
(1 fila)

INSERT 0 1
INSERT 0 1
ROLLBACK
```

Resultado por prueba:

| Prueba | Comando | Esperado | Resultado real | ¿OK? |
|---|---|---|---|---|
| 1A | `UPDATE pedido SET estado='PENDIENTE' WHERE id=1` (CONFIRMADO → PENDIENTE) | ERROR transición inválida | `ERROR: Transición inválida: CONFIRMADO → PENDIENTE` | ✅ |
| 1B | `UPDATE pedido SET estado='TERMINADO' WHERE id=8` (CONFIRMADO → TERMINADO) | UPDATE 1 | `UPDATE 1` | ✅ |
| 2A | `INSERT INTO detalle_pedido (pedido_id=1, ...)` (pedido CONFIRMADO) | ERROR bloqueo | `ERROR: No se pueden modificar detalles de un pedido en estado CONFIRMADO (pedido 1)` | ✅ |
| 2B | `INSERT INTO pedido` PENDIENTE + `INSERT INTO detalle_pedido` | INSERT 0 1 + INSERT 0 1 | `INSERT 0 1` (pedido 11) + `INSERT 0 1` | ✅ |

Además se verificó con `SELECT ... FROM pg_trigger` que los dos triggers de las reglas quedaron instalados en `copia_trabajo` tras el COMMIT de aplicación.

---

*Firma del estudiante: Ivana Gutierrez*