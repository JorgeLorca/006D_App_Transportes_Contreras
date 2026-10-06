import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error legible para mostrar al usuario en un SnackBar.
class RepositoryException implements Exception {
  RepositoryException(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Convierte un error de Postgres/Supabase en un mensaje entendible.
/// El detalle técnico completo queda en la consola.
RepositoryException traducirErrorPostgrest(
  PostgrestException e, {
  required String tabla,
  required String entidad,
}) {
  debugPrint('Supabase error ${e.code}: ${e.message} | ${e.details} | ${e.hint}');
  switch (e.code) {
    case '23505':
      return RepositoryException('Ya existe un registro de $entidad con esos datos.');
    case '42501':
      return RepositoryException(
          'Supabase rechazó la operación (RLS). Falta una política que permita insertar en "$tabla".');
    case '42703':
    case 'PGRST204':
      return RepositoryException('Una columna no existe en "$tabla": ${e.message}');
    case '23502':
      return RepositoryException('Falta un dato obligatorio en "$tabla": ${e.message}');
    default:
      return RepositoryException('Error de base de datos: ${e.message}');
  }
}