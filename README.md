# Food Store — Base de Datos

Trabajo Práctico Integrador — Base de Datos — UTN Facultad Regional Mendoza

Diseño e implementación de una base de datos relacional para la gestión de pedidos de un negocio de comidas. Toda la interacción se realiza mediante SQL sobre PostgreSQL: no hay interfaz de usuario ni aplicación.

## Requisitos

- PostgreSQL 16 o superior (`psql` o `pgAdmin`)
- Extensiones estándar únicamente (no requiere `CREATE EXTENSION` adicional)

## Estructura del repositorio

```
.
├── schema.sql          # Tipos ENUM, tablas, restricciones e índices
├── objects.sql         # Vistas, función, triggers y procedimiento almacenado
├── data.sql            # Datos de ejemplo (seed) para probar todas las consultas
├── queries.sql         # Una consulta resuelta y comentada por cada historia de usuario
├── transacciones.sql   # Escenarios de atomicidad, aislamiento y concurrencia
└── README.md
```

## Cómo crear la base

1. Crear una base de datos vacía:

   ```bash
   createdb food_store
   ```

2. Ejecutar los scripts **en este orden exacto** (cada uno depende del anterior):

   ```bash
   psql -d food_store -f schema.sql
   psql -d food_store -f objects.sql
   psql -d food_store -f data.sql
   ```

3. Verificar que la carga fue correcta:

   ```sql
   SELECT id, total FROM pedido ORDER BY id;
   -- Los totales no deberían ser 0: confirma que los triggers de subtotal/total funcionaron.
   ```

No ejecutar `data.sql` más de una vez sobre la misma base sin limpiarla antes: al no tener `ON CONFLICT`, una segunda ejecución duplicaría filas (los `nombre UNIQUE` de `categoria` sí lo bloquearían, pero usuario/producto/pedido no tienen esa protección salvo `mail`).

Para volver a empezar de cero:

```bash
dropdb food_store
createdb food_store
psql -d food_store -f schema.sql
psql -d food_store -f objects.sql
psql -d food_store -f data.sql
```

## Cómo reproducir las pruebas

### Historias de usuario (`queries.sql`)

Cada bloque está identificado con el código de la historia (`-- HU-CAT-01`, `-- HU-PED-02`, etc.). Se puede ejecutar el archivo completo:

```bash
psql -d food_store -f queries.sql
```

O copiar y pegar bloques individuales en `psql`/pgAdmin para revisar el resultado de una historia puntual.

### Transacciones y concurrencia (`transacciones.sql`)

Los escenarios de **atomicidad** y **transacción manual** (`COMMIT`/`ROLLBACK`) se ejecutan con una sola sesión:

```bash
psql -d food_store -f transacciones.sql
```

Los escenarios de **aislamiento** (`READ COMMITTED` vs `SERIALIZABLE`) y **bloqueos** (`SELECT ... FOR UPDATE`) requieren **dos sesiones simultáneas**, no se pueden reproducir corriendo el script de una sola vez:

1. Abrir dos terminales y conectar cada una con `psql -d food_store`.
2. Seguir el orden de comandos indicado en los comentarios del archivo, alternando entre la sesión 1 y la sesión 2 según se indica (`-- SESIÓN 1`, `-- SESIÓN 2`).
3. No cerrar ni hacer `COMMIT`/`ROLLBACK` en una sesión hasta que el comentario lo indique explícitamente — el orden entre sesiones es lo que reproduce el fenómeno de concurrencia.

## Notas de diseño

- **Borrado lógico:** ninguna tabla sufre `DELETE` físico en operación normal; todas usan la columna `eliminado`. Las vistas `v_*_vigentes` y `v_pedidos_resumen`/`v_pedido_detalle` ya filtran por `eliminado = FALSE`.
- **Total y subtotal:** son datos materializados (columnas reales), mantenidos automáticamente por triggers — no se deben actualizar a mano.
- **`data.sql` no usa `sp_crear_pedido`:** los pedidos de ejemplo se insertan directo en `pedido`/`detalle_pedido` para poder fijar fechas en distintos meses (el procedimiento usa siempre `CURRENT_DATE`). Por esto mismo, `data.sql` no descuenta stock — queda intacto para poder demostrar `CALL sp_crear_pedido(...)` en vivo durante el video con stock real disponible.

## Enlaces

- Video demostración: `<completar>`
- Documentación (PDF): `<completar o incluido en la raíz de este repositorio>`
