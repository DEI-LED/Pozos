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
#include "project.h"

#include "math.h"

#include "er.h"
#include "senal_a_emitir.h"

// Comandos de la PC
// Comando de inicio de adquisición
#define COMANDO_INICIO  'I'

#define TAM_BUF (2000 * 2)
uint8_t buf[TAM_BUF];

///////////////////////////////////
// Generado por el DMA Wizard.
///////////////////////////////////
/* Defines for DMA_DAC */
#define DMA_DAC_BYTES_PER_BURST 1
#define DMA_DAC_REQUEST_PER_BURST 1
#define DMA_DAC_SRC_BASE (senhalAEmitir)
#define DMA_DAC_DST_BASE (CYDEV_PERIPH_BASE)

/* Variable declarations for DMA_DAC */
/* Move these variable declarations to the top of the function */
static uint8 DMA_DAC_Chan;
static uint8 DMA_DAC_TD[1];
///////////////////////////////////
// Fin Generado por el DMA Wizard.
///////////////////////////////////

/*
Función que inicializa el DMA para el DAC. 
Generado por el DMA Wizard.
Parámetros:
    Ninguno
Retonro:
    Ninguno
*/
void inicDMA_DAC () {
    /* DMA Configuration for DMA_DAC */
    DMA_DAC_Chan = DMA_DAC_DmaInitialize(DMA_DAC_BYTES_PER_BURST, DMA_DAC_REQUEST_PER_BURST, 
        HI16(DMA_DAC_SRC_BASE), HI16(DMA_DAC_DST_BASE));
    DMA_DAC_TD[0] = CyDmaTdAllocate();
//                          DMA_DAC_TD[0], SINETABLE_SIZE, CY_DMA_DISABLE_TD, CY_DMA_TD_INC_SRC_ADR | CY_DMA_TD_AUTO_EXEC_NEXT
    CyDmaTdSetConfiguration(DMA_DAC_TD[0], SIGNAL_LENGTH, DMA_DAC_TD[0], CY_DMA_TD_INC_SRC_ADR);    //CY_DMA_DISABLE_TD
    CyDmaTdSetAddress(DMA_DAC_TD[0], LO16((uint32)senhalAEmitir), LO16((uint32)VDAC8_Data_PTR));
    CyDmaChSetInitialTd(DMA_DAC_Chan, DMA_DAC_TD[0]);
    CyDmaChEnable(DMA_DAC_Chan, 1);
}

/*
Función que inicializa todo el hardware necesario
Parámetros:
    Ninguno.
Retorno:
    Ninguno.
*/
void inicHardware () {
    PC_Start();
    MASTER_Start();
    VDAC8_Start();
    // inicializamos el DMA para generar la señal
    inicDMA_DAC ();
}

//int main(void)
//{
//    uint8_t ret;
//    
//    CyGlobalIntEnable; /* Enable global interrupts. */
//
//    /* Place your initialization/startup code here (e.g. MyInst_Start()) */
//    inicHardware ();
//    
//    for(;;)
//    {
//        /* Place your application code here. */
//        /* ---------------------------------------------------------------------
//            Este sistema espera un comando desde la PC para iniciar el proceso.
//            Cuando recibe el comando se inicia la emisión y luego se espera
//            por los datos adquiridos por el esclavo.
//        ------------------------------------------------------------------------*/
//        if (PC_GetChar() == COMANDO_INICIO) {
//            // iniciamos el proceso de emisión y activamos el trigger al esclavo para empezar adquisición
//            Inic_ADQ_Write(1);  
//            CyDelay(1);
//            Inic_ADQ_Write(0);
//            
//            // Esperamos los datos del esclavo
//            ret = recBytesChecksum (buf, TAM_BUF, MASTER_GetRxBufferSize, MASTER_GetChar);
//
//            // Procesar errores
//            if (ret == 0) {
//                PC_PutChar('c');    // no hay error
//                envBytesChecksum(buf, TAM_BUF, PC_PutChar);
//            } else {
//                PC_PutChar('e');    // error. Enviamos el valor de retorno de recBytesChecksum
//                PC_PutChar(ret + '0');
//            }
//        }
//    }
//}

////////////////////////////////////////////////////////////////////
// para probar el programa en Python
////////////////////////////////////////////////////////////////////

#define TAM_SENAL   2000
uint16_t senal[TAM_SENAL];

int main(void)
{
    uint16_t cont = 0;
    int i;

    CyGlobalIntEnable; /* Enable global interrupts. */

    /* Place your initialization/startup code here (e.g. MyInst_Start()) */
    PC_Start();
    
    // creamos una señal
    for (i = 0, cont = 0; i < TAM_SENAL; i++, cont = (cont +1) % 300) {
        senal[i] = (sin((4.0*M_PI)/2000.0*i) +1) * 2047;
    }
    
    for(;;)
    {
        /* Place your application code here. */
        // Esperamos el comando I
        while (PC_GetChar() != 'I');
        
        // esperamos un rato
        CyDelay(200);
        
//        PC_PutString("e4");
        
        // enviamos el carácter 'c'
        PC_PutChar('c');
        
        // enviamos la señal
        envBytesChecksum((uint8_t *)senal, TAM_SENAL * 2, PC_PutChar);
    }
}
/* [] END OF FILE */
