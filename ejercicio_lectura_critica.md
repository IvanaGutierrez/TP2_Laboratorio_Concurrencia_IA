# Ejercicio de Lectura Crítica — Parte 3

**Materia / TP:** Base de Datos II — TP2 Laboratorio Concurrencia IA, Parte 3
**Base involucrada:** esquema genérico de cátedra (no `food_store`)
**Fecha:** 2026-09-02

> **Nota de alcance:** Los dos scripts de esta parte operan sobre el esquema **genérico de cátedra** (tablas `funcion`, `pelicula`, `categoria`, `producto`), como indica la consigna en su sección 6.3. No pertenecen al proyecto Food Store (`food_store` no tiene tabla `funcion` ni `pelicula`); el ejercicio consiste en leerlos críticamente antes de ejecutarlos.

---

## 1. Contexto — por qué se lee antes de ejecutar (§6.1 y §6.2)

La consigna documenta cuatro incidentes reales con agentes de IA sobre bases de datos:

| Caso | Qué pasó |
|---|---|
| Replit — julio 2025 | El agente ignoró un congelamiento de código, ejecutó comandos destructivos y borró registros de más de 1.200 ejecutivos y 1.100 empresas. |
| Google Gemini CLI — julio 2025 | El agente asumió que una operación había funcionado sin confirmarla y encadenó pasos sobre una carpeta inexistente, destruyendo archivos reales. |
| Incidente «PocketOS» | Un agente con credenciales elevadas heredadas borró una base de producción y sus respaldos en segundos, pese a la orden de no ejecutar nada. |
| Confusión de entorno | Un desarrollador pidió limpiar datos de un entorno de prueba y el agente se conectó, sin error técnico, a la base de producción real y borró millones de filas. |

**El patrón común:** en ninguno de los casos el modelo «alucinó» código inválido ni fue atacado. La sintaxis fue correcta y la intención, razonable. Lo que falló fue el paso que un humano atento hace antes de ejecutar: confirmar contra qué base se corre, leer el **efecto real** del comando, y no confiar en el reporte del propio agente.

El protocolo de la Parte 0 (copia → transacción → respaldo) interpone exactamente esas tres salvaguardas. Este ejercicio entrena esa lectura: los dos scripts de abajo son sintácticamente válidos y "parecen" cumplir su objetivo, pero su **efecto real** no coincide con la consigna que dicen cumplir.

---

## 2. Script 1 — `UPDATE funcunes SET activa = FALSE`

### Script tal como está escrito

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

*(El primer comentario dice "funcunes" — un typo más. El problema real no es el typo, es el alcance del `UPDATE`.)*

### Qué haría realmente

Sin cláusula `WHERE`, el `UPDATE funcion SET activa = FALSE` recorre **todas y cada una de las filas** de la tabla `funcion` y pone `activa = FALSE` en todas ellas.

Una tabla `funcion` típica tiene funciones de películas **actualmente en cartel** y de películas **ya retiradas**. Este script no distingue: desactiva absolutamente todas las funciones, incluidas las de películas vigentes que hoy se están exhibiendo.

### Por qué no coincide con la consigna que dice cumplir

La intención declarada es **solo** dar de baja "las funciones de películas retiradas de cartel". El script, tal como está, da de baja **todas**. Es un caso clásico de `UPDATE` sin `WHERE`: la sentencia es correcta en sintaxis, pero su alcance es el doble (o más) de lo que se pedía. En producción esto significaría, por ejemplo, que una película que hoy tiene funciones activas deja de exhibirse sin ningún motivo comercial — o peor, dispara efectos en cadena sobre cualquier lógica que dependa de `activa`.

### Versión corregida

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE
WHERE pelicula_id IN (
    SELECT id FROM pelicula WHERE en_cartel = FALSE
);
```

**Explicación de la corrección:** se agrega el `WHERE` que delimita el alcance real: solo las funciones cuya película ya no está en cartel (`en_cartel = FALSE`). Así se preservan las funciones de películas vigentes. Si el esquema de `funcion` tuviera borrado lógico (`eliminado`), convendría además filtrar por `eliminado = FALSE` para no re-marcar funciones ya dadas de baja, en sintonía con el patrón de soft-delete del proyecto.

---

## 3. Script 2 — `DELETE FROM categoria ... NOT IN (...)`

### Script tal como está escrito

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### Qué haría realmente

La intención es borrar las categorías que no tienen ningún producto. Pero `NOT IN (SELECT ...)` tiene una trampa conocida con los **NULL**:

Si la subconsulta `SELECT categoria_id FROM producto` devuelve en su resultado siquiera **un** valor `NULL`, entonces la condición `id NOT IN (...)` no evalua a `TRUE` ni a `FALSE`, sino a **NULL** (por la lógica de tres valores de SQL: cualquier comparación con NULL da NULL). Y el `WHERE` **descarta toda fila cuya condición sea NULL**.

El resultado: el `DELETE` **no borra ninguna fila** — en silencio, sin error. El comando "funciona" (termina con éxito) pero no hace nada, cuando la intención era limpiar.

En el esquema genérico de cátedra, `producto.categoria_id` es normalmente una FK `NOT NULL`, por lo que en teoría no habría NULL. El problema aparece cuando hay **datos sucios** (registros que violan o perdieron la FK, o un diseño donde la columna es nullable) — exactamente el tipo de entorno real donde un script de limpieza suele ejecutarse. Además, hay una segunda consideración de dominio: si `producto` usa soft-delete (`eliminado`), ¿una categoría cuyos únicos productos están eliminados lógicamente se considera "sin productos asociados"? El script tal como está no lo decide.

### Por qué no coincide con la consigna que dice cumplir

La consigna promete "limpiar las categorías sin productos asociados". El script **o bien no borra nada** (si hay NULL en la subconsulta, borra 0 filas silenciosamente), **o bien** (si no hay NULL) borra correctamente pero sin tener en cuenta el criterio de soft-delete. En el peor caso, va a parecer que "funcionó" cuando en realidad no limpió nada — el usuario no notaría el error porque el comando termina sin error.

### Versión corregida

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1 FROM producto p
    WHERE p.categoria_id = c.id
      AND p.eliminado = FALSE
);
```

**Explicación de la corrección:**
- Se reemplaza `NOT IN` por `NOT EXISTS`: la condición `NOT EXISTS` evalúa correctamente ante filas NULL porque no depende de comparar contra un conjunto que pueda contener NULL — solo verifica si existe o no la fila asociada. Es **NULL-safe**.
- Se agrega `p.eliminado = FALSE` para que el criterio "categoría sin productos asociados" considere únicamente los productos **vigentes** (coherente con el patrón de borrado lógico del proyecto): si una categoría solo tiene productos eliminados lógicamente, se trata como categoría sin productos y se puede limpiar.

**Verificación adicional:** conviene confirmar antes si la FK `producto.categoria_id → categoria.id` está declarada con `ON DELETE RESTRICT` (como en Food Store). En ese caso, si por cualquier motivo quedara un producto físico apuntando a la categoría, el `DELETE` lanzaría una violación de integridad referencial en lugar de borrar en silencio — una protección útil, pero una razón más para probar siempre dentro de `BEGIN; ... ROLLBACK;` y revisar el resultado antes de `COMMIT` (protocolo de la Parte 0).

---

## 4. Conclusión

Los dos scripts comparten el mismo problema de fondo que los incidentes de la sección 6.1: son **sintácticamente válidos** y expresan una **intención razonable**, pero su **efecto real** diverge de lo que dicen hacer.

- Script 1: un `UPDATE` sin `WHERE` que afecta **más** de lo necesario (todas las funciones, en vez de solo las de películas retiradas).
- Script 2: un `DELETE ... NOT IN` que en presencia de NULL afecta **menos** de lo necesario (cero filas, en silencio).

Ninguno falla con un error de sintaxis; ambos parecen "funcionar". Por eso se leen línea por línea antes de ejecutarse, y por eso el protocolo de la Parte 0 obliga a correrlos dentro de `BEGIN; ... ROLLBACK;` sobre una copia: el costo de un script que no leemos no se mide en un mensaje de error, sino en datos que no vuelven.

---

*Firma del estudiante: COMPLETAR*
