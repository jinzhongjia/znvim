#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

#pragma comment(lib, "Ws2_32.lib")

int main() {
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        printf("WSAStartup failed.\n");
        return 1;
    }

    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == INVALID_SOCKET) {
        printf("Socket creation failed.\n");
        WSACleanup();
        return 1;
    }

    WSAPOLLFD fds[1];
    fds[0].fd = sock;
    fds[0].events = POLLPRI | POLLRDBAND;

    int ret = WSAPoll(fds, 1, -1);
    if (ret == SOCKET_ERROR) {
        printf("WSAPoll failed.\n");
        closesocket(sock);
        WSACleanup();
        return 1;
    }

    if (fds[0].revents & POLLPRI) {
        printf("Urgent data can be read.\n");
    }
    if (fds[0].revents & POLLRDBAND) {
        printf("Priority data can be read.\n");
    }

    closesocket(sock);
    WSACleanup();
    return 0;
}