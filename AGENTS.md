# AGENTS.md — TP2 Laboratorio Concurrency IA

## What this is

PostgreSQL schema for a food store app (university assignment). Single file: `schema.sql`.

## Database

- **Engine:** PostgreSQL (uses `GENERATED ALWAYS AS IDENTITY`, `TIMESTAMPTZ`, custom ENUMs).
- **Run schema:** execute `schema.sql` on an empty database.
- Tables: `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`.
- Soft-delete pattern: every table has `eliminado BOOLEAN DEFAULT FALSE`. Queries should filter `WHERE eliminado = FALSE` unless intentionally including deleted rows.
- `precio_unitario` in `detalle_pedido` must be captured at order time (not joined from `producto.precio`).

## Conventions

- All SQL is in Spanish (table/column names, enum values).
- Enum types: `rol`, `estado_pedido`, `forma_pago`.
- `ON DELETE RESTRICT` everywhere — no cascading deletes. Expect FK violations if deleting referenced rows.
