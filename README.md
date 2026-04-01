# Pozos

Sistema de adquisición y análisis de señales de transductores piezoeléctricos para ensayos de integridad de pilotes.

## Estructura del proyecto

```
Pozos/
├── PSoC/
│   ├── Transductor.cydsn/      # Firmware de acondicionamiento y adquisición de señal
│   └── Comunicacion.cydsn/     # Firmware de comunicación con la PC
└── Matlab/
    ├── interfaz_transductor.m  # Interfaz gráfica de adquisición de datos
    └── Analisis/               # Scripts de procesamiento y análisis de datos
```

## Componentes del sistema

- **PSoC CY8CKIT-059**: Plataforma embebida con ADC, amplificadores de transimpedancia y comunicación UART
- **MATLAB R2025b+**: Interfaz gráfica para adquisición en tiempo real y análisis de señales
