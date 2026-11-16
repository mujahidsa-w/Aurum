# PUBG-UNREAL

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

An Unreal Engine 4 battle royale prototype focused on gameplay systems built with Blueprints and C++.

> ## Multiplayer & mobile layer (this repository)
>
> This repository adds a C++ module (`PUBG_BP_Project/Source/PUBG_Blueprint`) on top of the
> original Blueprint project: real multiplayer (LAN rooms, direct IP, online rooms on dedicated
> servers), a lobby, server-authoritative combat and inventory, multi-touch mobile controls with a
> layout editor, graphics/FPS settings and Android/iOS configuration. **No existing Blueprint was
> edited or reparented**; single-player behaves exactly as before.
>
> The uploaded `PUBG-UNREAL-main.zip` only contains Git LFS pointer files, so the real assets must
> come from the original repository - see **[Docs/03-Build-And-Run.md](Docs/03-Build-And-Run.md)**.
>
> | Document (Arabic) | Contents |
> |---|---|
> | [01-Project-Analysis](Docs/01-Project-Analysis.md) | analysis of the original project, from its Blueprint binaries |
> | [02-Architecture](Docs/02-Architecture.md) | how the new layer works, authority model |
> | [03-Build-And-Run](Docs/03-Build-And-Run.md) | assets, build, editor tests, Android, iOS, dedicated server, room service |
> | [04-Editor-Integration](Docs/04-Editor-Integration.md) | what works automatically, optional Blueprint refactors |
> | [05-Testing-Report](Docs/05-Testing-Report.md) | what was tested and what still needs testing in Unreal |
>
> The C++ code was written without an Unreal Engine installation and has **not been compiled yet**;
> the logic, room service and convention checks that could run without the engine pass
> (`Tools/ci/run_all_tests.sh`).

## Overview

This project recreates core PUBG-style mechanics in UE4, with an emphasis on character movement, item interaction, inventory management, and weapon handling. The original prototype was single-player; the C++ layer described above adds multiplayer and mobile support.

Engine version: `UE 4.26.2`  
Project start: `May 2021`

## Features

- Three locomotion states: stand, crouch, and prone
- Speed changes for walking and running
- Loot pickup and interaction flow
- Equipment system for helmets, vests, and backpacks
- Inventory UI with drag-and-drop interactions
- Weapon switching, firing, reload, recoil, and aiming states
- First-person aiming and scope views

## Controls

| Action | Key |
| --- | --- |
| Move | `W A S D` |
| Look around | Mouse |
| Jump | `Space` |
| Crouch | `C` |
| Prone | `Z` |
| Walk | `Left Ctrl` |
| Run | `Left Shift` |
| Fire | `Left Mouse Button` |
| Open sight | `Right Mouse Button` |
| Normal aim | `Hold Right Mouse Button` |
| Reload | `R` |
| Change fire mode | `B` |
| Switch left weapon | `1` |
| Switch right weapon | `2` |
| Drop current weapon | `G` |
| Re-equip current weapon | `X` |
| Interact with item | `F` |
| Show inventory | `Tab` |
| Freelook | `Hold Left Alt` |
| Toggle map | `M` (planned) |
| In-game menu (new) | `Esc` / `F10` |

### Touch controls (new)

Left side: floating movement stick (light push = walk, push far up = sprint lock). Drag anywhere
free to look; the fire and aim buttons can also be dragged to aim. Buttons: FIRE (x2), ADS (hold),
SCOPE (tap), JUMP, CROUCH, PRONE, SPRINT, RELOAD, SWAP, BAG, PICK UP (appears near items), USE,
MODE, HOLSTER, EYE (free look), MENU, plus optional 1 / 2 / DROP / WALK. Every button injects the
same input action as the keyboard key above. MENU > EDIT BUTTON LAYOUT moves, resizes and hides them.

## Tech Stack

- Unreal Engine 4
- UE4 Blueprints
- C++

## Visuals

### Item system diagram

![Item UML diagram](https://user-images.githubusercontent.com/59629632/120907046-5319ea00-c62c-11eb-9c6e-663f3ed8eb8a.png)

### Inventory view

![Inventory UI](https://user-images.githubusercontent.com/59629632/120907225-d556de00-c62d-11eb-8831-cc69852b1bf3.png)

### Blueprint sample

![Blueprint sample](https://user-images.githubusercontent.com/59629632/120907255-09ca9a00-c62e-11eb-9fae-0875ad5c4759.png)

### Command center

![Command center](https://user-images.githubusercontent.com/59629632/120908813-54531300-c63c-11eb-9b45-fa0e40834948.png)

### Scope view

![Scope view](https://user-images.githubusercontent.com/59629632/120908816-6339c580-c63c-11eb-9d4d-f03be0eb5acf.png)

### Character pose state machine

![Locomotion state machine](https://user-images.githubusercontent.com/59629632/120908905-46ea5880-c63d-11eb-9773-c523fec6a675.png)

## Requirements

To open or extend the project, use Unreal Engine `4.26.2`. General UE4 hardware requirements apply; a quad-core CPU, dedicated GPU, and at least `8 GB` RAM are recommended for a smoother editor experience.

## Current Scope

- Single-player prototype (original Blueprints) plus the multiplayer / mobile C++ layer
- Focused on gameplay systems rather than live-service features
- Multiplayer: LAN rooms, direct IP, online rooms via `Tools/RoomService` and dedicated servers
- Known limits of the multiplayer layer are listed in `Docs/04-Editor-Integration.md`

## Contributing

Contributions are welcome:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push the branch
5. Open a pull request

## License

Released under the [MIT License](LICENSE).

### Assets

The MIT license covers this project's own code, Blueprints, and configuration.
It does **not** cover third-party Unreal Engine or Marketplace assets (meshes,
animations, textures, audio, and similar content) bundled or referenced here —
those remain under their respective licenses and copyrights, and are included
for prototype and demonstration purposes only.

## Contact

Zhenxiao Yu  
`zyu347@uwo.ca`

Project link: <https://github.com/zhenxiao-yu/PUBG-UNREAL>
