// Reflection helpers to read / write variables and call functions of the
// ORIGINAL Blueprints by name, without modifying or reparenting them.
//
// Every accessor checks the property type at runtime and returns false (and
// logs one warning per missing name) instead of crashing when a Blueprint is
// renamed or changed.

#pragma once

#include "CoreMinimal.h"

class UDataTable;
class FProperty;
class UScriptStruct;

namespace PUBGBridge
{
	// --- Object variables -------------------------------------------------------
	PUBG_BLUEPRINT_API bool GetBool(const UObject* Obj, FName Name, bool& Out);
	PUBG_BLUEPRINT_API bool SetBool(UObject* Obj, FName Name, bool Value);
	PUBG_BLUEPRINT_API bool GetFloat(const UObject* Obj, FName Name, float& Out);
	PUBG_BLUEPRINT_API bool SetFloat(UObject* Obj, FName Name, float Value);
	PUBG_BLUEPRINT_API bool GetInt(const UObject* Obj, FName Name, int32& Out);
	PUBG_BLUEPRINT_API bool SetInt(UObject* Obj, FName Name, int32 Value);
	/** Works for ByteProperty and EnumProperty (Blueprint enums). */
	PUBG_BLUEPRINT_API bool GetByte(const UObject* Obj, FName Name, uint8& Out);
	PUBG_BLUEPRINT_API bool SetByte(UObject* Obj, FName Name, uint8 Value);
	PUBG_BLUEPRINT_API bool GetName(const UObject* Obj, FName Name, FName& Out);
	PUBG_BLUEPRINT_API bool SetName(UObject* Obj, FName Name, FName Value);
	PUBG_BLUEPRINT_API bool GetString(const UObject* Obj, FName Name, FString& Out);
	PUBG_BLUEPRINT_API bool SetString(UObject* Obj, FName Name, const FString& Value);
	PUBG_BLUEPRINT_API bool GetText(const UObject* Obj, FName Name, FText& Out);
	PUBG_BLUEPRINT_API UObject* GetObject(const UObject* Obj, FName Name);
	PUBG_BLUEPRINT_API bool GetObjectArray(const UObject* Obj, FName Name, TArray<UObject*>& Out);
	PUBG_BLUEPRINT_API bool HasProperty(const UObject* Obj, FName Name);

	// --- Functions ---------------------------------------------------------------
	/** Calls a function whose first input parameter is numeric (float/int/byte). */
	PUBG_BLUEPRINT_API bool CallWithNumber(UObject* Obj, FName Function, double Value);
	/** Calls a function whose first input parameter is an object reference. */
	PUBG_BLUEPRINT_API bool CallWithObject(UObject* Obj, FName Function, UObject* Value);
	/**
	 * Calls a function and fills its input parameters, in declaration order,
	 * from the given strings (FProperty::ImportText). Missing values stay default.
	 */
	PUBG_BLUEPRINT_API bool CallWithTextArgs(UObject* Obj, FName Function, const TArray<FString>& Args);
	/**
	 * Calls a function after letting Fill write its input parameters. Inputs are the
	 * function's input FProperties in declaration order; Params is the parameter buffer.
	 * Return false from Fill to skip the call.
	 */
	PUBG_BLUEPRINT_API bool CallWithFiller(UObject* Obj, FName Function, TFunctionRef<bool(const TArray<FProperty*>& Inputs, uint8* Params)> Fill);
	/** Typed parameter writers for use inside CallWithFiller. */
	PUBG_BLUEPRINT_API bool WriteParamNumber(FProperty* Param, uint8* Params, double Value);
	PUBG_BLUEPRINT_API bool WriteParamText(FProperty* Param, uint8* Params, const FText& Value);
	PUBG_BLUEPRINT_API bool WriteParamObject(FProperty* Param, uint8* Params, UObject* Value);

	// --- User-defined struct rows (DataTables built from Blueprint structs) ------
	// Blueprint struct members are stored as "Name_12_<GUID>"; these helpers match
	// by the authored prefix ("Damage" matches "Damage_19_6234...").
	PUBG_BLUEPRINT_API bool GetStructFloat(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, float& Out);
	PUBG_BLUEPRINT_API bool GetStructInt(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, int32& Out);
	PUBG_BLUEPRINT_API bool GetStructBool(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, bool& Out);
	PUBG_BLUEPRINT_API bool GetStructByte(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, uint8& Out);
	PUBG_BLUEPRINT_API bool GetStructName(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, FName& Out);
	PUBG_BLUEPRINT_API bool GetStructText(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, FText& Out);
	/** Hard or soft object reference; soft references are resolved, loading synchronously if needed. */
	PUBG_BLUEPRINT_API UObject* GetStructObject(const UScriptStruct* Struct, const void* Row, const TCHAR* Field);
	/** Soft path of an object field without loading it. */
	PUBG_BLUEPRINT_API FSoftObjectPath GetStructObjectPath(const UScriptStruct* Struct, const void* Row, const TCHAR* Field);

	// --- DataTables ---------------------------------------------------------------
	/** Loads (once) and caches a DataTable referenced by soft path. */
	PUBG_BLUEPRINT_API UDataTable* LoadTable(const FSoftObjectPath& Path);
	/** Raw row memory, or nullptr. */
	PUBG_BLUEPRINT_API const uint8* FindRow(const UDataTable* Table, FName RowName);

	/** Logs a warning only the first time a given key is seen. */
	PUBG_BLUEPRINT_API void WarnOnce(const FString& Key, const FString& Message);
}
