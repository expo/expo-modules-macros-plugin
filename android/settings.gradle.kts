pluginManagement {
  repositories {
    mavenCentral()
    gradlePluginPortal()
    google()
  }
}

dependencyResolutionManagement {
  repositories {
    mavenCentral()
    google()
  }
}

rootProject.name = "expo-modules-macros"

include(":annotations")
include(":processor")
