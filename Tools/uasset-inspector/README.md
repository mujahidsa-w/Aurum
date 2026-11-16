# uasset-inspector

Read-only helpers used to analyse the project's Blueprint binaries without the
Unreal Editor (UE 4.26 package format, FileVersionUE4 = 522).

| Script | What it prints |
|---|---|
| `uasset_dump.py summary <files>` | parent class, functions, graphs, K2 node counts, components |
| `uasset_dump.py names|imports <files>` | name table / imported engine functions |
| `bp_vars.py <files>` | Blueprint member variables and struct fields (with types) |
| `cdo_dump.py <files>` | class-default values (e.g. socket names in `MyGameInstance`) |
| `count_calls.py <files>` | which Blueprints use `GetPlayerController(0)`-style accessors |

The scripts need real `.uasset` files, not Git LFS pointer stubs. To fetch only
the Blueprint folder from the original repository:

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/zhenxiao-yu/PUBG-UNREAL
cd PUBG-UNREAL && git lfs pull --include="PUBG_BP_Project/Content/Blueprints/**"
python3 Tools/uasset-inspector/uasset_dump.py summary PUBG_BP_Project/Content/Blueprints/Gameplay/*.uasset
```

They never modify the files they read.
