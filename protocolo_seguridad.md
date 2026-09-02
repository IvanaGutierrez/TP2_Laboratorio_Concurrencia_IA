# Protocolo Operativo de Seguridad — Scripts IA sobre PostgreSQL

Cada vez que se aplica un script generado por IA sobre la base de datos, se ejecutan estos tres pasos **en orden**. Sin excepción.

## Entorno

- **Motor:** PostgreSQL (base original: `foodStore`, definida en `schema.sql`).
- **Cliente SQL:** psql (terminal) y DBeaver (GUI).
  - **psql:** ejecutar `.sql` con `psql -U postgres -d <base> -f <archivo>.sql`, o copiar/pegar los bloques `BEGIN; ... ROLLBACK;` directamente en la terminal.
  - **DBeaver:** abrir la conexión correspondiente, abrir una "SQL Editor" (Alt+X) y ejecutar los mismos bloques `BEGIN; ... ROLLBACK;` con el icono ▶. DBeaver muestra "filas afectadas" en la pestaña de resultados de cada instrucción.
- **Valores reales del entorno:** usuario de PostgreSQL = `postgres`, base original = **`foodStore`** (con `S` mayúscula; el `README.md` la llama `food_store`, pero en este servidor se creó como `foodStore`). **Ojo:** por ser un identificador con mayúscula, en los comandos debe ir entre comillas dobles: `"foodStore"` (si se escribe `foodStore` sin comillas, PostgreSQL lo normaliza a minúsculas y falla). Todos los comandos usan estos valores.
- **Nunca** se toca la base original: todo el protocolo corre contra `copia_trabajo`.

---

## Paso 1 — Copia de trabajo

**Objetivo:** nunca tocar la base original. Toda operación se hace sobre una copia.

```bash
createdb -U postgres -T "foodStore" copia_trabajo
```

Si la copia ya existe de una sesión anterior, eliminarla y recrearla:

```bash
dropdb -U postgres copia_trabajo
createdb -U postgres -T "foodStore" copia_trabajo
```

**psql:**

```sql
-- Alternativa desde dentro de psql (requiere superuser)
DROP DATABASE IF EXISTS copia_trabajo;
CREATE DATABASE copia_trabajo TEMPLATE "foodStore";
```

**DBeaver:** crear nueva conexión apuntando a `copia_trabajo` en el mismo servidor.

> La base original (`foodStore`) queda intacta. Si algo sale mal, no hay nada que restaurar en la original.

---

## Paso 2 — Transacción con ROLLBACK

**Objetivo:** toda escritura (INSERT, UPDATE, DELETE, ALTER) se ejecuta dentro de una transacción que se revierte antes de confirmar, para inspeccionar el efecto real.

### 2.1 Envolver el script

**psql (terminal):** crear el archivo `script_ia.sql` (con BEGIN y ROLLBACK ya dentro) y ejecutarlo contra la copia:

```bash
psql -U postgres -d copia_trabajo -f script_ia.sql
```

El contenido del archivo (el bloque ROLLBACK es el que te permite inspeccionar después):

```sql
BEGIN;

-- === INICIO DEL SCRIPT GENERADO POR IA ===

INSERT INTO producto (nombre, precio, stock, id_categoria)
VALUES ('Pan integral', 850.00, 50, 1);

UPDATE producto SET precio = 900.00 WHERE nombre = 'Pan integral';

DELETE FROM producto WHERE eliminado = TRUE;

-- === FIN DEL SCRIPT GENERADO POR IA ===

ROLLBACK;  -- SIEMPRE rollback primero
```

> Al terminar, psql muestra el mensaje `ROLLBACK` y (si se usó `\set VERBOSITY verbose`) los errores. Como el bloque se revierte, la copia queda igual que antes.

**DBeaver:** abrir una SQL Editor (Alt+X) en la conexión `copia_trabajo`, pegar el mismo bloque `BEGIN; … ROLLBACK;`, seleccionar todo y ejecutar con ▶. DBeaver muestra en la salida "Rows affected" por cada INSERT/UPDATE/DELETE y el estado de la transacción. Lo mismo se puede hacer sin pegar el archivo: lotes `BEGIN; … ROLLBACK;` pegados en el editor.

### 2.2 Inspeccionar antes de decidir

Después de `ROLLBACK`, revisar qué habría pasado:

```sql
-- Verificar integridad referencial
SELECT dp.id_producto, p.nombre
FROM detalle_pedido dp
LEFT JOIN producto p ON p.id_producto = dp.id_producto
WHERE p.id_producto IS NULL;

-- Verificar que no se borran datos referenciados
SELECT COUNT(*) FROM detalle_pedido
WHERE id_producto IN (
    SELECT id_producto FROM producto WHERE eliminado = TRUE
);
```

### 2.3 Confirmar solo si todo está bien

Si la inspección es satisfactoria, volver a ejecutar el script y esta vez hacer COMMIT:

```sql
BEGIN;

-- Mismo script de antes
INSERT INTO producto (nombre, precio, stock, id_categoria)
VALUES ('Pan integral', 850.00, 50, 1);

-- ...

COMMIT;  -- Solo si la inspección del ROLLBACK fue OK
```

> **Regla:** si el script produce errores, mensajes inesperados, o afecta filas que no debería, se queda en ROLLBACK y se revisa con el agente IA antes de reintentar. La ejecución con COMMIT se hace de la misma forma (psql con el archivo, o DBeaver en el editor de la conexión `copia_trabajo`).

---

## Paso 3 — Respaldo antes de cambios estructurales

**Objetivo:** antes de ALTER, DROP, CREATE INDEX, o cualquier migración que modifique el esquema, hacer un pg_dump de la copia de trabajo para poder restaurar sin depender solo del ROLLBACK.

### 3.1 Dump antes de modificar

**Terminal (psql):** `pg_dump` es una herramienta de línea de comandos, no se ejecuta dentro de psql. Correr en la terminal (PowerShell o cmd) directamente, parado en la raíz del repo:

```bash
pg_dump -U postgres -Fc copia_trabajo > respaldo_pre_alter.dump
```

Formato SQL plano (legible) como alternativa:

```bash
pg_dump -U postgres copia_trabajo > respaldo_pre_alter.sql
```

> Si `pg_dump` no está en el PATH, abrir la consola desde pgAdmin "PSQL Tool" o agregar la ruta del binario, por ejemplo: `& "C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" -U postgres -Fc copia_trabajo > respaldo_pre_alter.dump` (ajustá la versión).

**DBeaver:** DBeaver no expone `pg_dump` directamente de fábrica; el camino recomendado es correr el comando de terminal de arriba y verificar el resultado desde DBeaver (conectar a `copia_trabajo` y revisar esquema/datos). Si querés el dump desde la GUI: botón derecho sobre `copia_trabajo` → Herramientas → Backup… (en versiones recientes invoca `pg_dump` por debajo) y guardá el archivo en la raíz del repo.

### 3.2 Ejecutar el cambio estructural dentro de transacción

```sql
BEGIN;

ALTER TABLE producto ADD COLUMN codigo_barras VARCHAR(13);
CREATE INDEX idx_producto_codigo ON producto(codigo_barras);

ROLLBACK;  -- Inspeccionar, luego decidir
```

### 3.3 Restaurar si algo sale mal

**Terminal (psql):** si el cambio estructural corrompió la copia o el resultado no es recuperable con ROLLBACK:

```bash
# Eliminar la copia corrupta
dropdb -U postgres copia_trabajo

# Recrear desde el dump
createdb -U postgres copia_trabajo
pg_restore -U postgres -d copia_trabajo respaldo_pre_alter.dump
```

Si se usó formato SQL plano:

```bash
dropdb -U postgres copia_trabajo
createdb -U postgres copia_trabajo
psql -U postgres -d copia_trabajo -f respaldo_pre_alter.sql
```

**DBeaver:** después de restaurar por terminal, refrescar la conexión (F5 o botón derecho → Refresh) para ver el estado real de `copia_trabajo`. Si el dump se hizo por GUI, la restauración es: botón derecho sobre `copia_trabajo` → Herramientas → Restore… y elegir el archivo del dump.

> **Regla:** el dump se guarda en la raíz del repo. Se puede borrar después de confirmar que el cambio estructural funciona, pero nunca antes.

---

## Resumen del flujo

```
┌─────────────────────────────────────────────────────┐
│  1. COPIA                                           │
│     createdb -T "foodStore" copia_trabajo     │
│                                                     │
│  2. TRANSACCIÓN                                     │
│     BEGIN → script → ROLLBACK → inspeccionar        │
│     Si OK → BEGIN → script → COMMIT                 │
│                                                     │
│  3. RESPALDO (solo para cambios estructurales)       │
│     pg_dump → cambios → ROLLBACK → restaurar si     │
│     algo falla                                      │
└─────────────────────────────────────────────────────┘
```

## Notas

- **Nunca** ejecutar scripts directamente sobre `foodStore`. Siempre sobre `copia_trabajo`.
- Los scripts de solo lectura (SELECT, EXPLAIN) no requieren transacción pero sí se ejecutan contra `copia_trabajo`.
- Los dumps se guardan en la raíz del repositorio como `respaldo_pre_alter.dump`.
- Si el script tiene errores de sintaxis SQL, corregirlo antes de aplicar el protocolo.
