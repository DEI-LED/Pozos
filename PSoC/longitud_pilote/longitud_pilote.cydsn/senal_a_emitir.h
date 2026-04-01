/* ========================================
 *
 * Copyright YOUR COMPANY, THE YEAR
 * All Rights Reserved
 * UNPUBLISHED, LICENSED SOFTWARE.
 *
 * CONFIDENTIAL AND PROPRIETARY INFORMATION
 * WHICH IS THE PROPERTY OF your company.
 *
 * ========================================
*/

#ifndef SENAL_A_EMITIR_H
#define SENAL_A_EMITIR_H

#include "project.h"
#include <stdint.h>

// Cantidad de muestras de la señal a emitir
#define	SIGNAL_LENGTH	81

// señal a emitir. Esta en Flash, en zona de programa. Debe empezar en una página de 64Kbytes.
CYCODE const uint8_t senhalAEmitir[SIGNAL_LENGTH] __attribute__((aligned(65536))) = { 
    128, 129, 129, 128, 126, 125, 123, 121, 120, 121, 124, 130, 136, 143, 147, 146, 
    139, 127, 110, 94, 84, 86, 100, 127, 160, 189, 202, 193, 160, 110, 59, 25, 23, 
    58, 121, 192, 243, 255, 219, 147, 66, 7, 0, 35, 111, 191, 242, 243, 196, 124, 
    59, 29, 45, 94, 152, 191, 196, 169, 127, 92, 80, 92, 119, 144, 155, 150, 135, 
    119, 111, 113, 122, 131, 135, 134, 129, 125, 123, 124, 126, 128, 127
};

#endif
/* [] END OF FILE */
