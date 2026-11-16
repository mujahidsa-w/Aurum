#include "Lobby/PUBGLobbyGameState.h"

#include "Net/UnrealNetwork.h"

void APUBGLobbyGameState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(APUBGLobbyGameState, RoomName);
	DOREPLIFETIME(APUBGLobbyGameState, bHasPassword);
	DOREPLIFETIME(APUBGLobbyGameState, MaxPlayers);
	DOREPLIFETIME(APUBGLobbyGameState, BattleMapName);
	DOREPLIFETIME(APUBGLobbyGameState, bDedicatedServer);
	DOREPLIFETIME(APUBGLobbyGameState, JoinCode);
	DOREPLIFETIME(APUBGLobbyGameState, HostAddress);
	DOREPLIFETIME(APUBGLobbyGameState, CountdownEndTime);
	DOREPLIFETIME(APUBGLobbyGameState, bTravelling);
}

float APUBGLobbyGameState::GetCountdownRemaining() const
{
	if (CountdownEndTime < 0.f)
	{
		return -1.f;
	}
	return FMath::Max(0.f, CountdownEndTime - GetServerWorldTimeSeconds());
}
