/*
3.5) Servidor
* Ejecución en forma concurrente. Limita inicialmente a 10 instancias child.
* Espera conexiones por el port TCP 5024. Cuando se reciba una conexión cree un child. 
* Cada instancia child buscará un port local UDP libre a partir del port 10000. 
* Cuando lo encuentra lo informa al cliente por el port TCP heredado, y queda esperando información por el port UDP. 
* La información que recibirá por dicho puerto UDP, serán logs remotos, y cada child deberá presentar en pantalla la información recibida.
* Condición de finalización de los procesos child: El proceso child debe recibir cada 30 segundos por el port UDP mencionado algún dato. 
* Transcurridos 2 minutos sin recibir mensajes, cierra el socket UDP y termina su ejecución. 
* Usar función select con timeout para este fin.
* Condición de finalización del proceso principal: 1 minuto sin child activo y sin pedidos de conexión entrantes (las dos condiciones). 
* Usar función select.
*/

#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/select.h>   
#include <sys/time.h>

#define MYPORT 5024    //Numero de puerto donde se conectaran los clientes
#define BACKLOG 10     // Tamaño de la cola de conexiones recibidas 
#define PORTUDPINICIAL 10000
#define MAXBUFLEN 100  // Max. cantidad de bytes que podra recibir 

void handlerChild(int val); // Prototipo de la funcion handler linkeada a señal SIGCHLD

int child_count = 0;    // Contador de procesos hijos, para saber si ya no hay ninguno activo

int main()
{		
	// Variables para chequear finalizacion de proceso Padre
	/* fd_set es un tipo (una estructura interna) que representa un conjunto de descriptores (file descriptors). 
	Se usa para indicar qué sockets quiero vigilar para lectura */
	fd_set readfdsPadre; 
    struct timeval timeoutPadre;
    int status;            // Esta variable y la siguiente son para una funcion waitpid que verifica el estado de los procesos hijos 
	pid_t pid;

	// Variables Socket TCP
    int sockfdTCP;     				   // El servidor escuchara por sockfdTCP 
    int newfdTCP;      				   // Las transferencias de datos se realizar mediante newfdTCP 
    struct sockaddr_in my_addrTCP;     // contendra la direccion IP y el numero de puerto local 
    struct sockaddr_in their_addrTCP;  // Contendra la direccion IP y numero de puerto del cliente 
    int sin_sizeTCP;  				   // Contendra el tamanio de la escructura sockaddr_in */

    int numeroCliente = 0;

    if ((sockfdTCP = socket(AF_INET, SOCK_STREAM, 0)) == -1) //Crea un socket y verifica si hubo algun error
    {
        perror("socket");
        exit(1);
    }

	// Asignamos valores a la estructura my_addrTCP para luego poder llamar a la funcion bind() 
    my_addrTCP.sin_family = AF_INET;
    my_addrTCP.sin_port = htons(MYPORT); 	   //debe convertirse a network byte order porque es enviado por la red*/
    my_addrTCP.sin_addr.s_addr = INADDR_ANY;   // automaticamente usa la IP local */
    bzero(&(my_addrTCP.sin_zero), 8);  		   // rellena con ceros el resto de la estructura */
    if ( bind(sockfdTCP, (struct sockaddr *)&my_addrTCP, sizeof(struct sockaddr)) == -1)
    {
    	perror("bind");
    	exit(1);
    }
	// Habilitamos el socket para recibir conexiones, con una cola de 5 conexiones en espera como maximo 
	printf("Esperando conexiones ...\n");
    if (listen(sockfdTCP, BACKLOG) == -1)
    {
        perror("listen");
        exit(1);
    }
    while(1)  // loop que llama a accept() 
    {	
    	// Antes de usar select() siempre debo hacer esto:
    	FD_ZERO(&readfdsPadre); //Inicializa (pone a 0) el conjunto readfdsPadre. Siempre llamar antes de usar FD_SET
    	FD_SET(sockfdTCP, &readfdsPadre); //Añade sockfdTCP al conjunto readfdsPadre. select() avisa cuando haya datos para leer en este descriptor

    	// Hago select() y segun lo que devuelva veo que hago
    	/* Argumentos de select:
    	int select(int nfds, 		 //El valor más alto de los descriptores a vigilar + 1
           fd_set *readfdsPadre,     //Conjunto de descriptores a vigilar para lectura (datos disponibles)
           fd_set *writefds, 		 //Conjunto de descriptores a vigilar para escritura (puedo enviar datos sin bloquearme)
           fd_set *exceptfds,		 //Conjunto para condiciones excepcionales (ej. errores fuera de banda)
           struct timeval *timeout); //Tiempo máximo a esperar

        Devuelve:
        > 0	Número de descriptores listos. Indica que al menos uno de los sockets está listo para la operación que querías (lectura/escritura/excepción).
		  0	Timeout alcanzado: ningún socket estuvo listo en el tiempo indicado.
		 -1	Error: algo salió mal (por ejemplo, un descriptor inválido). errno se usa para más detalles */
    	
    	// Tiempo para 1 minuto sin child activo
    	timeoutPadre.tv_sec = 60;   
    	timeoutPadre.tv_usec = 0;

        int activityPadre = select(sockfdTCP + 1, &readfdsPadre, NULL, NULL, &timeoutPadre);

        // Si hubo error al hacer select()
	    if (activityPadre < 0) 
	    {
	        perror("select");
	        break;
	    }

	    // Si pasaron 60 segundos sin recibir conexiones, vencio el timeoutPadre, entra aca
	    else if (activityPadre == 0) 
	    {	
	    	printf("Servidor: 1 minuto sin conexiones ... esperando que no queden hijos activos...\n");
        	// cargo handler que se linkea con la señal SIGCHLD que enviaran los hijos al terminar
			signal(SIGCHLD, handlerChild);
			// El padre se queda aca hasta que todos los procesos hijos finalicen, ahi child_count sera = 0
         	while (child_count>0) 
  				sleep(5);
			printf("Ya no hay procesos hijos activos ... cerrando servidor y finalizando proceso...\n");
			close(sockfdTCP);
			return 0; // Aca finaliza el proceso padre
	    }

	    // Si llegó una nueva conexión TCP
	    /* select() modifica readfdsPadre dejándolo solo con los descriptores listos. 
	    FD_ISSET comprueba si sockfdTCP quedó marcado como “listo”. Si es así, se puede recv()/accept() según corresponda */
	    else if (FD_ISSET(sockfdTCP, &readfdsPadre)) 
	    {
	       	sin_sizeTCP = sizeof(struct sockaddr_in); //Se espera por conexiones 
	        if ((newfdTCP = accept(sockfdTCP, (struct sockaddr *)&their_addrTCP, &sin_sizeTCP)) == -1)
	        {
	            perror("accept");
	            continue;  // Si se produce un error se finaliza el programa 
	        }
	        printf  ("Server: conexion desde:  %s\n", inet_ntoa(their_addrTCP.sin_addr));
	        
	        numeroCliente++; //Para asignar un numero de cliente a cada conexion gestionada por los hijos, lo hago en el padre para que cada hijo reciba la copia
	                         //con un numero mas
	        //Veo si hubo mas de 10 conexiones
	        if (numeroCliente > BACKLOG) //Si hubo mas de 10, cierro la que se acepto
	        {
				printf ("No se pueden aceptar mas conexiones, cerrando ...\n");
	        	close(newfdTCP);
	        }
	        else if (!fork()) //Si no, creo proceso hijo con la conexion entrante
	        {	// Aca comienza el proceso hijo 

	        	// Variables para chequear finalizacion de procesos hijos
				fd_set readfdsHijos; 
				struct timeval timeoutHijos;
				int idle_time = 0; // tiempo acumulado sin mensajes

		        // Variables Socket UDP
				int sockfdUDP;
				struct sockaddr_in my_addrUDP;    // direccion IP y numero de puerto local 
				struct sockaddr_in their_addrUDP; // direccion IP y numero de puerto del cliente 
				int numbytes; 				      //numbytes: numero de bytes recibidos 
				char buffer[MAXBUFLEN];   		  // Buffer de recepcion
				int addr_len; 					  //addr_len contendra el tamanio de la estructura sockaddr_in
				addr_len = sizeof(struct sockaddr);
				int puerto;
				char msg[64];
				char filename[50];

				// Se crea el socket UDP
				if ((sockfdUDP = socket(AF_INET, SOCK_DGRAM, 0)) == -1)
				{
					perror("Fallo la creacion del socket UDP");
					exit(1);
				}
				// Intenta hacer bind desde el puerto 10000, si encuentra uno libre sale del loop
				for (puerto = PORTUDPINICIAL; puerto < 65000; puerto++)
				{
					my_addrUDP.sin_family = AF_INET;     	  // host byte order 
					my_addrUDP.sin_port = htons(puerto);      // network byte order 
					my_addrUDP.sin_addr.s_addr = INADDR_ANY;  // se asigna automaticamente la direccion IP local 
					bzero(&(my_addrUDP.sin_zero), 8);  	   // rellena con ceros el resto de la estructura 
					// Se le da un nombre al socket */
					if (bind(sockfdUDP, (struct sockaddr *)&my_addrUDP, sizeof(struct sockaddr))  == -1)
					{
						perror("No pudo encontrar puerto libre");
					}
					else //Si pudo encontrar el puerto
					{	
						break;
					}
				}
				printf("El puerto encontrado es el: %d\n",puerto);

				// Cuando lo encuentra lo informa al cliente por el port TCP heredado, y queda esperando información por el port UDP
				sprintf(msg, "Numero de puerto UDP: %d", puerto);
	            if (send(newfdTCP, msg, strlen(msg), 0) == -1)
	                perror("send");
	            
	            // Ahora se queda esperando info del cliente cada 30 segundos, sino a los 2 minutos cierro socket udp

	            while (1)
	            {
		            FD_ZERO(&readfdsHijos);
	    			FD_SET(sockfdUDP, &readfdsHijos);

	    			// Las variables de timeout se deben reinicializar en cada ciclo del while, antes de llamar a select porque este las puede modificar
	    			timeoutHijos.tv_sec = 10;
			    	timeoutHijos.tv_usec = 0;

				    int activityHijos = select(sockfdUDP+1, &readfdsHijos, NULL, NULL, &timeoutHijos);

				    // Si hubo error al hacer select()
				    if (activityHijos < 0) 
				    {
				        perror("select");
				        break;
				    }

				    else if (activityHijos == 0) 
				    {
				        // Timeout 30s sin datos
				        idle_time += 10;
				        printf ("Pasaron %d segundos sin recibir logs de cliente %d ... \n",idle_time,numeroCliente);
				        if (idle_time >= 40) 
				        {
				            printf("Child %d: Cerrando conexion UDP de cliente %d ...\n", getpid(),numeroCliente);
				            close(sockfdUDP);
				            exit(0);
				        }
				    } 
				    else if (FD_ISSET(sockfdUDP, &readfdsHijos)) // Si recibo por UDP muestro en pantalla el mensaje
				    {
				        if ((numbytes=recvfrom(sockfdUDP, buffer, MAXBUFLEN, 0, (struct sockaddr *)&their_addrUDP, &addr_len)) == -1)
						{
							perror("recvfrom");
							exit(1);
						} 
						if (numbytes > 0)
						{
							buffer[numbytes] = '\0';
				        	printf("Child %d: log recibido: %s\n", getpid(), buffer);
				        	idle_time = 0; // resetear inactividad	
						}
				    }
				}
	    	}
	    	// Esto es lo que hace el padre
	    	close(newfdTCP);
	        child_count++;        
    	}
	}
	// Si sali del while(1) que acepta conexiones TCP debido al timeout de 1 minuto y ya sin hijos activos, cierro el socketTCP que abrio el padre
	close(sockfdTCP);
	printf("Servidor apagado correctamente.\n");
}

//Handler linkeado a SIGCHLD para decrementar contador de procesos hijos
void handlerChild(int val)
{
	// espero la señal SIGCHLD de cualquier hijo
	wait(0);
	printf("Finaliza el hijo %d",val);
	// decremento cantidad de hijos
	child_count--;
}