# Declaración de Uso de IA (DUIA) — Parte 3: Ejercicio de Lectura Crítica

**Materia / TP:** Base de Datos II — TP2 Laboratorio Concurrencia IA, Parte 3
**Base involucrada:** esquema genérico de cátedra (no se ejecutó nada sobre ninguna base)
**Fecha:** 2026-09-02

---

## Herramienta

OpenCode (asistente de código con IA). Sesión de análisis de scripts SQL para el ejercicio de lectura crítica (§6.3).

## Spec o prompt utilizado

Resumen del prompt dado al asistente:

> "Resolver la Parte 3 del TP: analizar los dos scripts de la consigna §6.3 (el `UPDATE funcion SET activa = FALSE` y el `DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto)`). Para cada uno: identificar qué filas afectaría realmente tal como está escrito, explicar por qué eso no coincide con la consigna que dice cumplir, y dar la versión corregida (con su WHERE, o con el manejo correcto de NULL en la subconsulta). Contextualizar con los casos reales de §6.1 y el patrón común de §6.2. Generar `ejercicio_lectura_critica.md`."

## Qué generó

- **Archivo `ejercicio_lectura_critica.md`:** la estructura completa del entregable con:
  - Contexto (§6.1 y §6.2): los 4 casos reales y el patrón común.
  - **Script 1** (`UPDATE funcion SET activa = FALSE`): análisis de que sin `WHERE` afecta **todas** las filas de `funcion` (incluso las de películas en cartel), por qué no cumple la consigna, y la corrección `... WHERE pelicula_id IN (SELECT id FROM pelicula WHERE en_cartel = FALSE)`.
  - **Script 2** (`DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto)`): análisis del problema de `NOT IN` con NULL (si la subconsulta devuelve un NULL, la condición evalúa NULL y el `DELETE` borra **cero filas** en silencio), por qué no cumple la consigna, y la corrección con `NOT EXISTS` + filtro de soft-delete `p.eliminado = FALSE`.
  - Conclusión sobre el patrón común de por qué se lee antes de ejecutar.

## Qué se aceptó

- El **análisis del Script 1** tal cual lo propuso la IA: UPDATE sin WHERE = afecta todas las filas; corrección con filtro por películas retiradas.
- El **análisis del Script 2** tal cual lo propuso la IA: el problema del `NOT IN` con NULL (semántica de tres valores: NULL no es TRUE, el WHERE descarta); corrección con `NOT EXISTS` (NULL-safe) y decisión sobre soft-delete.
- La **estructura del archivo** (secciones por script + contexto + conclusión).

## Qué se modificó o descartó, y por qué

- **Se descartó un primer borrador** que el asistente entregó "en modo Plan" (solo describía lo que haría sin escribir el archivo): se reutilizó el análisis pero se escribió el archivo directamente.
- **Se ajustó el alcance del análisis del Script 2 para mencionar el soft-delete** (`eliminado`): el esquema del proyecto Food Store usa borrado lógico, y aunque el ejercicio es sobre el esquema genérico de cátedra, el criterio "categoría sin productos asociados" debe considerar si solo cuentan los productos vigentes. Es una mejora respecto del borrador inicial, que solo mencionaba el problema de NULL.
- **Se agregó la verificación adicional de la FK `ON DELETE RESTRICT`** en la corrección del Script 2, porque en el proyecto Food Store esa FK existe y cambia el comportamiento esperado del DELETE (violación de integridad referencial en lugar de borrado silencioso).

## Verificación realizada

- El análisis es **puramente de lectura de código SQL** (no se ejecutó nada contra ninguna base, ni siquiera contra la copia de trabajo). Verificación por razonamiento sobre la semántica SQL:
  - Script 1: `UPDATE` sin cláusula `WHERE` → alcance = todas las filas (comportamiento definido por el estándar SQL).
  - Script 2: `x NOT IN (subconsulta con NULL)` → resultado NULL para todo x no presente → `WHERE` falso → 0 filas afectadas (semántica de tres valores lógicos de SQL).
  - Se contrastaron las correcciones contra el esquema real del proyecto (nombres de columnas `eliminado`, `categoria_id`, claves foráneas) para que fueran coherentes con los patrones del proyecto.
- Resultado: ambos análisis se consideran correctos y verificables de forma independiente; el ejercicio es de lectura crítica, por lo que la verificación de "qué haría el script" es conceptual y no de ejecución (los scripts ni siquiera pertenecen al esquema Food Store, como indica la consigna §6.3).

---

*Firma del estudiante: Ivana Gutierrez*