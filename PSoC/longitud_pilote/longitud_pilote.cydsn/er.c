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

#include <stdint.h>

#include "clock_config.h"

// implementación del timeout, se usa un contador que cuenta 
// las veces en el ciclo de espera, cuando este valor supera
// al de T_ESPERA se sale por timeout.
// Debe estar definido FRECUENCIA_CLOCK_CONFIG con la frecuencia
// de operación de microprocesador.
#define T_ESPERA	((FRECUENCIA_CLOCK_CONFIG / 60) * 2)	// aprox. dos segundo

/*
Función que recibe exactamente una cantidad dada de bytes.
Los dos primeros bytes corresponde a la cantidad de bytes que se van a recibir. 
Es un valor uint16_t, el primer byte recibido es el menos significativo.
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
uint8_t recBytesChecksum (uint8_t *buf, uint16_t tam, uint8_t (*hayDato)(), uint8_t (*gc)(void)) {
	uint32_t cont = 0;
    uint16_t tamRec = 0, tamEjec = 0;
    uint8_t ret = 0, tmp, cs;
    
    // recibimos la cantidad de bytes que se están enviando
    for (cont = 0; !hayDato() && cont < T_ESPERA; cont++);
    if (cont >= T_ESPERA) return 4;	// timeout, termina inmediatamente
    cs = tmp = (gc() & 0xFF);
    tamRec = (((uint16_t)tmp & 0xFF));

    for (cont = 0; !hayDato() && cont < T_ESPERA; cont++);
    if (cont >= T_ESPERA) return 4;	// timeout, termina inmediatamente
    cs += (tmp = gc() & 0xFF);
    tamRec |= (((uint16_t)tmp & 0xFF) << 8);

	if (tamRec > tam) {
		ret = 1;
		tamEjec = tam;	// si el tamaño recibido es mayor que el espacio disponible, se recibe solo hasta el espacio disponible
	} else if (tamRec < tam) {
		ret = 2;
		tamEjec = tamRec;	// se guarda el dato transmitido completo
	} else {
        ret = 0;
        tamEjec = tam;  // los tamaños coinciden
	}
    
    // recibimos cantidad
	for (; tamEjec--; buf++) {
        for (cont = 0; !hayDato() && cont < T_ESPERA; cont++);
	    if (cont >= T_ESPERA) return 4;	// timeout, termina inmediatamente
        cs += (*buf = gc() & 0xFF);
    }
	// recibimos el resto si tamRec > tam
	if (ret == 1) {
		for (tamEjec = (tamRec - tam) * sizeof(uint8_t); tamEjec--; ) {
        	for (cont = 0; !hayDato() && cont < T_ESPERA; cont++);
        	if (cont >= T_ESPERA) return 4;	// timeout, termina inmediatamente
            tmp = gc();
			cs += tmp;	// sumamos el checksum, pero desechamos el dato
		}
	}
    // Recibimos el checksum
    for (cont = 0; !hayDato() && cont < T_ESPERA; cont++);
	if (cont >= T_ESPERA) return 4;	// timeout, termina inmediatamente
    tmp = gc() & 0xFF;
	if (tmp != cs) return 3;	// error de checksum
	return ret;
}

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
uint8_t recBytes (uint8_t *buf, uint16_t tam, uint8_t (*hayDato)(), uint8_t (*gc)(void)) {
	uint32_t cont = 0;
    
	for (; tam--; buf++) {
        for (cont = 0; !hayDato() && cont < T_ESPERA; cont++);
	    if (cont >= T_ESPERA) return 4;	// timeout, termina inmediatamente
        *buf = gc() & 0xFF;
    }
    return 0;
}

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
void envBytes (uint8_t *buf, uint16_t tam, void (*pc)(uint8_t)) {
    
	for (; tam--; buf++) {
        pc(*buf);   // enviamos el dato
    }
}

/*
Función que envía exactamente una cantidad dada de bytes.
Los primeros dos bytes contienen la cantidad de bytes a enviar
en un valor de 16 bits, el primer byte es el valor menos significativo.
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
void envBytesChecksum (uint8_t *buf, uint16_t tam, void (*pc)(uint8_t)) {
    uint8_t cs = 0, tmp;
    
    // enviamos la cantidad
    tmp = tam & 0xFFu;
    cs = tmp;
    pc (tmp);

    tmp = (tam >> 8) & 0xFFu;
    cs += tmp;
    pc (tmp);
    
    // enviamos los datos
	for (; tam--; buf++) {
        cs += *buf;
        pc(*buf);   // enviamos el dato
    }
    
    // enviamos el checksum
    pc(cs);
}
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
uint8_t calculaCompCheckSum (uint8_t *v, uint16_t tam) {
    uint8_t cs;

    for (cs = 0; --tam; v++) {
        cs += *v;
    }

    if (cs == *v)
        return 0;
    else
        return 1;
}

/*
Función que calcula el checksum de un vector según se define en esta aplicación.
Parámetros:
    v -> vector con los bytes 
    tam -> cantidad de bytes. 
Retorno:
El checksum calculado
*/
uint8_t calculaCheckSum (uint8_t *v, uint16_t tam) {
    uint8_t cs;

    for (cs = 0; tam--; v++) {
        cs += *v;
    }

    return cs;
}

/* [] END OF FILE */
