#include "Lobby/PUBGLobbyPlayerState.h"

#include "Network/PUBGPlayerProfileComponent.h"

APUBGLobbyPlayerState::APUBGLobbyPlayerState()
{
	Profile = CreateDefaultSubobject<UPUBGPlayerProfileComponent>(TEXT("PUBGProfile"));
	NetUpdateFrequency = 10.f;
}
