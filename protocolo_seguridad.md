# Protocolo de Seguridad y Manejo de Concurrencia

## 1. Control de Acceso y Credenciales
- No commitear contraseñas o credenciales de la base de datos en el repositorio.
- Usar usuarios con permisos mínimos necesarios para cada operación.

## 2. Manejo de Transacciones e Aislamiento
- Monitorear el nivel de aislamiento de transacciones (READ COMMITTED, REPEATABLE READ, SERIALIZABLE) según el caso de uso.
- Evitar transacciones abiertas de larga duración para prevenir bloqueos (*locks*) innecesarios.

## 3. Integridad de Datos
- Garantizar que las operaciones de actualización de stock usen bloqueos explícitos (FOR UPDATE) cuando sea necesario para evitar condiciones de carrera (*race conditions*).
- Validar siempre restricciones de clave foránea e integridad referencial antes de confirmar un COMMIT.
