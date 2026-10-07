/// Feature flags locales de AquaControl.
///
/// Demostrador de la Parte F (Ruta 1) de la práctica de CI/CD: permite
/// ocultar/mostrar un módulo en tiempo de "build" sin tocar el resto de la
/// lógica de negocio. Hoy es una constante local; el plan a futuro (ya
/// definido en el Plan DevOps del Proyecto Móvil) es moverla a Firebase
/// Remote Config para poder cambiarla en producción sin nueva publicación.
class FeatureFlags {
  /// Controla si la pestaña "Reportes" (aún en desarrollo) se muestra en
  /// la navegación principal de la app.
  static const bool featureNewReports = false;
}

