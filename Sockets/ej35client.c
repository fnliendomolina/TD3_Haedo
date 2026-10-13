/*
3.5) Cliente
* Se ejecuta mediante el siguiente comando: sender [argumento]
* En donde sender es el nombre del programa ejecutable, y argumento es un archivo de texto existente en el cliente.
* El programa debe conectar con el servidor anteriormente definido al port TCP
* Posteriormente leer de a bloques de 50 bytes el archivo de texto recibido por argumento, y enviar al puerto UDP indicado por el Servidor. 
* Repetir esta secuencia cada 30 segundos, enviando los bloques subsiguientes hasta finalizar el archivo.
* El cliente termina al finalizar el envío del archivo de texto completo
*/

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <netdb.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/select.h>   
#include <sys/time.h>

#define PORT 5024         // El puerto donde se conectara
#define MAXDATASIZE 100   // maxima cant. De bytes que se pueden recibir en una llamada a recv 
#define BYTESLECTURA 50   // Cantida de bytes que leera del archivo

int main(int argc, char *argv[])
{
    // Variables para lectura de archivo
    char buffer[BYTESLECTURA];
    int n;

	// Variables para conexion TCP
    int sockfdTCP, numbytes; 		   // Contendra el numero de bytes recibidos despues de llamar a recv() 
    char buf[MAXDATASIZE];  		   // Buffer donde se reciben los datos por UDP
    struct hostent *he;      		   // Se utiliza para convertir el nombre del host a su direccion IP 
    struct sockaddr_in their_addrTCP;  // direccion del server donde se conectara 

    // Variables para conexion UDP
    int sockfdUDP;
	struct sockaddr_in their_addrUDP;  /*  Almacenara la direccion IP y numero de puerto UDP del servidor */

    int puertoUDP;

    // Tratamiento de la linea de comandos. 
    if (argc != 2)
    {
        fprintf(stderr,"usage: client hostname\n");
        exit(1);
    }

    // Creamos el socket 
    if ((sockfdTCP = socket(AF_INET, SOCK_STREAM, 0)) == -1)
    {
        perror("socket");
        exit(1);
    }

    // Establecemos parametros de conexion TCP con el servidor
    their_addrTCP.sin_family = AF_INET;
    their_addrTCP.sin_port = htons(PORT);
    their_addrTCP.sin_addr.s_addr = inet_addr("127.0.0.1"); // IP del servidor
    bzero(&(their_addrTCP.sin_zero), 8);

    // Intentamos conectarnos con el servidor 
    if (connect(sockfdTCP, (struct sockaddr *)&their_addrTCP, sizeof(struct sockaddr)) == -1)
    {
        perror("connect");
        exit(1);
    }

    // Recibimos los datos del servidor, en este caso el PORT UDP que encuentra cada child del server
    if ((numbytes = recv(sockfdTCP, buf, MAXDATASIZE, 0)) == -1)
    {
        perror("recv");
        exit(1);
    }

    // Visualizamos lo recibido 
    buf[numbytes] = '\0';
    printf("Recibido: %s\n",buf);

    // Guardo el numero de puerto como entero
    sscanf(buf, "Numero de puerto UDP: %d", &puertoUDP);
    printf("El puerto a eviar por UDP es el Nº: %d\n",puertoUDP);

    // Abro el archivo con el nombre pasado como argumento, en modo lectura
    FILE *fp = fopen(argv[1], "r");

    // Abro conexion UDP y establezco parametros de conexion UDP con el servidor
    if ((sockfdUDP = socket(AF_INET, SOCK_DGRAM, 0)) == -1)
    {
        perror("socket");
        exit(1);
    }
    their_addrUDP.sin_family = AF_INET;  /* host byte order */
    their_addrUDP.sin_port = htons(puertoUDP);  /* network byte order */
    their_addrUDP.sin_addr.s_addr = inet_addr("127.0.0.1"); // IP del servidor
    bzero(&(their_addrUDP.sin_zero), 8);

    // Voy leyendo de a 50 bytes, mientras pueda leer sigue enviando, cuando termina cierra el archivo y ambos sockets
    while ((n = fread(buffer, 1, BYTESLECTURA, fp)) > 0) 
    {
        // Lee de a 50 bytes y envia
        if ((numbytes = sendto(sockfdUDP, buffer, n, 0, (struct sockaddr *)&their_addrUDP, sizeof(struct sockaddr))) == -1)
        {
            perror("sendto");
            exit(1);
        }
        printf("Enviado log de 50 bytes\n");
        sleep(10); // esperar 30 segundos
    }

    // Al terminar de leer archivo cierro todo
    printf("El archivo leido finalizo, no hay mas logs por enviar, cerrando conexion\n");
    fclose(fp);
    close(sockfdTCP);
    close(sockfdUDP);
    return 0;
}