# TP2 Laboratorio — Concurrencia e IA como motor primario

**UNIVERSIDAD TECNOLÓGICA NACIONAL**
**Tecnicatura Universitaria en Programación a Distancia**
**BASE DE DATOS II — Unidad 1 · Integridad, Transacciones y Concurrencia (Semana 2)**

Trabajo Práctico de Laboratorio: Concurrencia e IA como motor primario.
Se trabaja sobre el esquema del propio proyecto integrador (Food Store), con OpenCode y Kiro como herramientas y con el protocolo de seguridad de la cátedra como condición no negociable en cada paso.

> **Regla de fondo:** se delega la escritura, nunca la decisión. Todo lo que la IA propone se lee, se prueba sobre una copia y dentro de una transacción, y se defiende oralmente antes de darlo por bueno.

---

## Entregables del TP2

| Parte | Entregable | Archivos |
|---|---|---|
| **Parte 0** | Protocolo de seguridad (copia, transacción, respaldo) adaptado al entorno real | `protocolo_seguridad.md` |
| **Parte 1** | Restricciones de integridad versionadas + DUIA | `restricciones_integridad.sql`, `restricciones_integridad_test.sql`, `aplicar_restricciones.sql`, `DUIA_parte1.md` |
| **Parte 2** | Informe de concurrencia (4 escenarios con 2 sesiones, IA verificada en el motor) + DUIA | `informe_concurrencia.md`, `parte2_concurrencia.sql`, `DUIA_parte2.md` |
| **Parte 3** | Ejercicio de lectura crítica + DUIA | `ejercicio_lectura_critica.md`, `DUIA_parte3.md` |
| **Base** | Esquema propio del proyecto integrador (Food Store) | `schema.sql`, `objects.sql`, `data.sql`, `queries.sql`, `transacciones.sql` |

---

## Estructura del repositorio

```
.
├── protocolo_seguridad.md       # Parte 0 — protocolo de 3 pasos adaptado al entorno
├── restricciones_integridad.sql # Parte 1 — reglas de negocio garantizadas en el motor
├── restricciones_integridad_test.sql  # Parte 1 — 4 pruebas (válidas e inválidas)
├── aplicar_restricciones.sql    # Parte 1 — solo el DDL de las restricciones (para COMMIT)
├── DUIA_parte1.md               # Parte 1 — Declaración de Uso de IA
├── informe_concurrencia.md      # Parte 2 — informe con 4 escenarios verificados
├── parte2_concurrencia.sql      # Parte 2 — scripts de Sesión A/B para reproducir
├── DUIA_parte2.md               # Parte 2 — Declaración de Uso de IA
├── ejercicio_lectura_critica.md # Parte 3 — análisis de los 2 scripts peligrosos
├── DUIA_parte3.md               # Parte 3 — Declaración de Uso de IA
├── schema.sql                   # Base — tipos ENUM, tablas, restricciones e índices
├── objects.sql                  # Base — vistas, función, triggers y procedimiento
├── data.sql                     # Base — datos de ejemplo (seed)
├── queries.sql                  # Base — consultas por historia de usuario
├── transacciones.sql            # Base — escenarios de atomicidad/concurrencia
└── README.md
```

---

## Requisitos

- PostgreSQL 18 o superior (`psql` o `pgAdmin`)
- Extensiones estándar únicamente (no requiere `CREATE EXTENSION` adicional)
- Base real del entorno: **`foodStore`** (con `S` mayúscula — ver nota abajo)

> ⚠️ **Nombre de la base:** en este entorno la base original se llama `foodStore` (no `food_store` del README original). Por tener mayúscula, en los comandos debe ir entre **comillas dobles**: `"foodStore"`. Si se escribe sin comillas, PostgreSQL normaliza a minúsculas y falla.

---

## Cómo crear la base

1. Crear la base original y cargar los scripts **en este orden exacto** (cada uno depende del anterior):

   ```bash
   createdb -U postgres "foodStore"
   psql -U postgres -d foodStore -f schema.sql
   psql -U postgres -d foodStore -f objects.sql
   psql -U postgres -d foodStore -f data.sql
   ```

2. Verificar que la carga fue correcta:

   ```sql
   SELECT id, total FROM pedido ORDER BY id;
   -- Los totales no deberían ser 0: confirma que los triggers de subtotal/total funcionaron.
   ```

3. **Nunca trabajar sobre `foodStore`.** Antes de aplicar cualquier script generado por IA, crear la copia de trabajo (protocolo Parte 0):

   ```bash
   createdb -U postgres -T "foodStore" copia_trabajo
   ```

   Y ejecutar todo sobre `copia_trabajo`, dentro de `BEGIN; ... ROLLBACK;`, con respaldo `pg_dump` antes de cambios estructurales. Detalle completo en `protocolo_seguridad.md`.

---

## Cómo reproducir las partes del TP2

### Parte 1 — Restricciones (sobre `copia_trabajo`)

```bash
# Prueba completa (aplica restricciones + 4 pruebas, termina en ROLLBACK)
psql -U postgres -d copia_trabajo -f restricciones_integridad_test.sql

# Aplicar SOLO las restricciones (persistir con COMMIT)
BEGIN; \i aplicar_restricciones.sql; COMMIT;   # o -f con el archivo
```

Las 4 pruebas: 1A y 2A **deben fallar** (retroceso de estado / detalle en pedido cerrado), 1B y 2B **deben pasar** (avance válido / detalle en pedido pendiente). Resultados reales en `DUIA_parte1.md`.

### Parte 2 — Concurrencia (requiere DOS sesiones psql simultáneas)

```bash
psql -U postgres -d copia_trabajo    # Sesión A
psql -U postgres -d copia_trabajo    # Sesión B (otra terminal)
```

Seguir el orden de comandos de `parte2_concurrencia.sql` alternando entre sesiones. Escenarios: lectura no repetible, lectura fantasma, espera por bloqueo (`FOR UPDATE`) e interbloqueo (40P01). Salidas reales y verificación de la IA en el motor en `informe_concurrencia.md`.

### Parte 3 — Lectura crítica

Análisis conceptual (no requiere base): `ejercicio_lectura_critica.md` identifica qué haría realmente cada script antes de mostrar la versión corregida.

---

## Contexto: el esquema del proyecto integrador (Food Store)

Base de datos relacional para la gestión de pedidos de un negocio de comidas, sobre PostgreSQL.

- **Tablas:** `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`.
- **Tipos ENUM:** `rol`, `estado_pedido` (`PENDIENTE`, `CONFIRMADO`, `TERMINADO`, `CANCELADO`), `forma_pago`.
- **Triggers:** subtotal y total automáticos en `detalle_pedido`/`pedido` (`objects.sql`); congela `precio_unitario` al momento del pedido.
- **Procedimiento `sp_crear_pedido`:** crea el pedido completo de forma atómica, bloquea el stock con `SELECT ... FOR UPDATE` (evita sobreventa concurrente) y descuenta stock; si cualquier ítem falla, revierte todo (rollback).

### Notas de diseño

- **Borrado lógico:** ninguna tabla sufre `DELETE` físico en operación normal; todas usan la columna `eliminado`. Las vistas `v_*_vigentes` y `v_pedidos_resumen`/`v_pedido_detalle` ya filtran por `eliminado = FALSE`.
- **Total y subtotal:** son datos materializados (columnas reales), mantenidos automáticamente por triggers — no se deben actualizar a mano.
- **`data.sql` no usa `sp_crear_pedido`:** los pedidos de ejemplo se insertan directo en `pedido`/`detalle_pedido` para poder fijar fechas en distintos meses (el procedimiento usa siempre `CURRENT_DATE`).
- **Restricciones de la Parte 1 son triggers, no CHECK:** la Regla 1 compara `OLD.estado` vs `NEW.estado` (un CHECK no puede), y la Regla 2 consulta el estado del pedido padre (un CHECK no admite subconsultas).

---

## Protocolo de seguridad (Parte 0) — resumen

1. **Copia:** `createdb -U postgres -T "foodStore" copia_trabajo` — nunca tocar la original.
2. **Transacción:** todo script que escribe corre primero dentro de `BEGIN; ... ROLLBACK;` para inspeccionar el efecto antes de decidir.
3. **Respaldo:** `pg_dump -U postgres -Fc copia_trabajo > respaldo_pre_alter.dump` antes de cualquier cambio estructural.

Detalle adaptado al entorno real (PostgreSQL 18, psql/DBeaver) en `protocolo_seguridad.md`.