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
#include <stdint.h>

/*
Función que recibe exactamente una cantidad dada de bytes.
Los dos primeros bytes corresponde a la cantidad de bytes que se van a recibir. 
Es un valor uint16_t, el primer byte recibido es el más significativo.
Luego se espera recibir una determinada cantidad de bytes (tam). Si se recibe 
menos bytes se guarda lo que se recibe. Si se reciben más bytes, se guarda lo
que se puede (tam bytes) y lo demás se desecha. 
Siempre se revisa el checksum. 
Sale de la función cuando recibe todos los bytes o se produce el timeout.
Parámetros:
    buf -> donde se guardan los bytes
    tam -> cantidad de bytes a recibir. Sin incluir los 2 bytes del tamaño ni el checksum
    hayDato -> función que retorna la cantidad de bytes en el buffer de recepción del puerto serial
    gc  -> función que recibe un byte. Función GetByte de PSoC.
Retorno:
 * 0 si no hay error
 * 1 error: no hay lugar en el vector local
 * 2 error: se reciben menos datos que los esperados
 * 3 error de checksum
 * 4 error de timeout, esperamos demasiado por los datos
*/
uint8_t recBytesChecksum (uint8_t *buf, uint16_t tam, uint8_t (*hayDato)(), uint8_t (*gc)(void));

/*
Función que recibe exactamente una cantidad dada de bytes.
Sale de la función cuando recibe todos los bytes o se produce el timeout.
Parámetros:
    buf -> donde se guardan los bytes
    tam -> cantidad de bytes a recibir
    hayDato -> función que retorna la cantidad de bytes en el buffer de recepción del puerto serial
    gc  -> función que recibe un byte. Función GetByte de PSoC.
Retorno:
 * 0 si no hay error
 * 4 error de timeout, esperamos demasiado por los datos
*/
uint8_t recBytes (uint8_t *buf, uint16_t tam, uint8_t (*hayDato)(), uint8_t (*gc)(void));

/*
Función que envía exactamente una cantidad dada de bytes.
Sale de la función cuando envía todos los bytes. 
Parámetros:
    buf -> donde se guardan los bytes
    tam -> cantidad de bytes a enviar
    pc  -> función que envía un byte. Función PutChar del PSoC.
Retorno:
Ninguno.
*/
void envBytes (uint8_t *buf, uint16_t tam, void (*pc)(uint8_t));

/*
Función que envía exactamente una cantidad dada de bytes.
Los primeros dos bytes contienen la cantidad de bytes a enviar
en un valor de 16 bits, el primer byte es el valor más significativo.
Al final de la transmisión se envía un byte que corresponde al checksum,
que se forma sumando todos los bytes transmitidos, incluidos los de 
cantidad.
Los valores se envían tal como están en memoria. Es decir, para el 
ARM Cortex M3 sería little endian
Parámetros:
    buf -> donde se guardan los bytes a enviar
    tam -> cantidad de bytes a enviar
    pc  -> función que envía un byte. Función PutChar del PSoC.
Retorno:
Ninguno.
*/
void envBytesChecksum (uint8_t *buf, uint16_t tam, void (*pc)(uint8_t));

/*
Función que calcula y verifica el checksum. Se supone que el último
byte es el checksum recibido y este no se suma.
Parámetros:
    v -> vector con los bytes recibidos
    tam -> cantidad de bytes recibidos. Incluido el checksum recibido, el último byte
Retorno:
0 -> verificación correcta
1 -> error en el checksum
*/
uint8_t calculaCompCheckSum (uint8_t *v, uint16_t tam);

/*
Función que calcula el checksum de un vector según se define en esta aplicación.
Parámetros:
    v -> vector con los bytes 
    tam -> cantidad de bytes. 
Retorno:
El checksum calculado
*/
uint8_t calculaCheckSum (uint8_t *v, uint16_t tam);

/* [] END OF FILE */
