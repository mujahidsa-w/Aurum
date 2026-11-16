#include "Core/PUBGBlueprintBridge.h"

#include "PUBG_Blueprint.h"
#include "Engine/DataTable.h"
#include "UObject/UnrealType.h"
#include "UObject/SoftObjectPtr.h"

namespace PUBGBridge
{
	namespace
	{
		TSet<FString>& WarnedKeys()
		{
			static TSet<FString> Keys;
			return Keys;
		}

		FProperty* FindProp(const UObject* Obj, FName Name)
		{
			if (!Obj || Name.IsNone())
			{
				return nullptr;
			}
			FProperty* Prop = FindFProperty<FProperty>(Obj->GetClass(), Name);
			if (!Prop)
			{
				WarnOnce(Obj->GetClass()->GetName() + TEXT(".") + Name.ToString(),
					FString::Printf(TEXT("Blueprint variable '%s' not found on %s (check UPUBGSettings::BlueprintNames)."),
						*Name.ToString(), *Obj->GetClass()->GetName()));
			}
			return Prop;
		}

		FNumericProperty* AsNumeric(FProperty* Prop)
		{
			if (!Prop)
			{
				return nullptr;
			}
			if (FEnumProperty* EnumProp = CastField<FEnumProperty>(Prop))
			{
				return EnumProp->GetUnderlyingProperty();
			}
			return CastField<FNumericProperty>(Prop);
		}

		bool ReadNumber(FProperty* Prop, const void* Container, double& Out)
		{
			FNumericProperty* Num = AsNumeric(Prop);
			if (!Num || !Container)
			{
				return false;
			}
			const void* Value = Prop->ContainerPtrToValuePtr<void>(Container);
			Out = Num->IsFloatingPoint() ? Num->GetFloatingPointPropertyValue(Value) : (double)Num->GetSignedIntPropertyValue(Value);
			return true;
		}

		bool WriteNumber(FProperty* Prop, void* Container, double In)
		{
			FNumericProperty* Num = AsNumeric(Prop);
			if (!Num || !Container)
			{
				return false;
			}
			void* Value = Prop->ContainerPtrToValuePtr<void>(Container);
			if (Num->IsFloatingPoint())
			{
				Num->SetFloatingPointPropertyValue(Value, In);
			}
			else
			{
				Num->SetIntPropertyValue(Value, (int64)FMath::RoundToDouble(In));
			}
			return true;
		}

		const FProperty* FindField(const UScriptStruct* Struct, const TCHAR* Field)
		{
			if (!Struct || !Field)
			{
				return nullptr;
			}
			const FString Exact(Field);
			const FString Prefix = Exact + TEXT("_");
			for (TFieldIterator<FProperty> It(Struct); It; ++It)
			{
				const FString PropName = It->GetName();
				if (PropName.Equals(Exact, ESearchCase::IgnoreCase) || PropName.StartsWith(Prefix, ESearchCase::IgnoreCase))
				{
					return *It;
				}
			}
			WarnOnce(Struct->GetName() + TEXT(".") + Exact,
				FString::Printf(TEXT("Field '%s' not found in struct %s."), Field, *Struct->GetName()));
			return nullptr;
		}

		/** Allocates and initializes a parameter buffer for Function, calls Fill, then ProcessEvent. */
		template <typename FillFn>
		bool CallFunction(UObject* Obj, FName FunctionName, FillFn&& Fill)
		{
			if (!Obj)
			{
				return false;
			}
			UFunction* Function = Obj->FindFunction(FunctionName);
			if (!Function)
			{
				WarnOnce(Obj->GetClass()->GetName() + TEXT("::") + FunctionName.ToString(),
					FString::Printf(TEXT("Blueprint function '%s' not found on %s."), *FunctionName.ToString(), *Obj->GetClass()->GetName()));
				return false;
			}
			const int32 Size = FMath::Max<int32>(Function->ParmsSize, 1);
			uint8* Params = (uint8*)FMemory_Alloca(Size);
			FMemory::Memzero(Params, Size);

			TArray<FProperty*, TInlineAllocator<8>> Inputs;
			for (TFieldIterator<FProperty> It(Function); It && It->HasAnyPropertyFlags(CPF_Parm); ++It)
			{
				It->InitializeValue_InContainer(Params);
				if (!It->HasAnyPropertyFlags(CPF_ReturnParm | CPF_OutParm) || It->HasAnyPropertyFlags(CPF_ReferenceParm))
				{
					Inputs.Add(*It);
				}
			}

			const bool bOk = Fill(Inputs, Params);
			if (bOk)
			{
				Obj->ProcessEvent(Function, Params);
			}

			for (TFieldIterator<FProperty> It(Function); It && It->HasAnyPropertyFlags(CPF_Parm); ++It)
			{
				It->DestroyValue_InContainer(Params);
			}
			return bOk;
		}

		// Weak pointers + AddToRoot: a static map of strong pointers would be
		// destroyed after the UObject system shuts down and crash on exit.
		TMap<FSoftObjectPath, TWeakObjectPtr<UDataTable>>& TableCache()
		{
			static TMap<FSoftObjectPath, TWeakObjectPtr<UDataTable>> Cache;
			return Cache;
		}
	}

	void WarnOnce(const FString& Key, const FString& Message)
	{
		bool bAlreadyInSet = false;
		WarnedKeys().Add(Key, &bAlreadyInSet);
		if (!bAlreadyInSet)
		{
			UE_LOG(LogPUBG, Warning, TEXT("%s"), *Message);
		}
	}

	bool HasProperty(const UObject* Obj, FName Name)
	{
		return Obj && !Name.IsNone() && FindFProperty<FProperty>(Obj->GetClass(), Name) != nullptr;
	}

	bool GetBool(const UObject* Obj, FName Name, bool& Out)
	{
		if (FBoolProperty* Prop = CastField<FBoolProperty>(FindProp(Obj, Name)))
		{
			Out = Prop->GetPropertyValue_InContainer(Obj);
			return true;
		}
		return false;
	}

	bool SetBool(UObject* Obj, FName Name, bool Value)
	{
		if (FBoolProperty* Prop = CastField<FBoolProperty>(FindProp(Obj, Name)))
		{
			Prop->SetPropertyValue_InContainer(Obj, Value);
			return true;
		}
		return false;
	}

	bool GetFloat(const UObject* Obj, FName Name, float& Out)
	{
		double V = 0.0;
		if (ReadNumber(FindProp(Obj, Name), Obj, V))
		{
			Out = (float)V;
			return true;
		}
		return false;
	}

	bool SetFloat(UObject* Obj, FName Name, float Value)
	{
		return WriteNumber(FindProp(Obj, Name), Obj, Value);
	}

	bool GetInt(const UObject* Obj, FName Name, int32& Out)
	{
		double V = 0.0;
		if (ReadNumber(FindProp(Obj, Name), Obj, V))
		{
			Out = (int32)V;
			return true;
		}
		return false;
	}

	bool SetInt(UObject* Obj, FName Name, int32 Value)
	{
		return WriteNumber(FindProp(Obj, Name), Obj, Value);
	}

	bool GetByte(const UObject* Obj, FName Name, uint8& Out)
	{
		double V = 0.0;
		if (ReadNumber(FindProp(Obj, Name), Obj, V))
		{
			Out = (uint8)FMath::Clamp<int32>((int32)V, 0, 255);
			return true;
		}
		return false;
	}

	bool SetByte(UObject* Obj, FName Name, uint8 Value)
	{
		return WriteNumber(FindProp(Obj, Name), Obj, Value);
	}

	bool GetName(const UObject* Obj, FName Name, FName& Out)
	{
		if (FNameProperty* Prop = CastField<FNameProperty>(FindProp(Obj, Name)))
		{
			Out = Prop->GetPropertyValue_InContainer(Obj);
			return true;
		}
		return false;
	}

	bool SetName(UObject* Obj, FName Name, FName Value)
	{
		if (FNameProperty* Prop = CastField<FNameProperty>(FindProp(Obj, Name)))
		{
			Prop->SetPropertyValue_InContainer(Obj, Value);
			return true;
		}
		return false;
	}

	bool GetString(const UObject* Obj, FName Name, FString& Out)
	{
		if (FStrProperty* Prop = CastField<FStrProperty>(FindProp(Obj, Name)))
		{
			Out = Prop->GetPropertyValue_InContainer(Obj);
			return true;
		}
		return false;
	}

	bool SetString(UObject* Obj, FName Name, const FString& Value)
	{
		if (FStrProperty* Prop = CastField<FStrProperty>(FindProp(Obj, Name)))
		{
			Prop->SetPropertyValue_InContainer(Obj, Value);
			return true;
		}
		return false;
	}

	bool GetText(const UObject* Obj, FName Name, FText& Out)
	{
		if (FTextProperty* Prop = CastField<FTextProperty>(FindProp(Obj, Name)))
		{
			Out = Prop->GetPropertyValue_InContainer(Obj);
			return true;
		}
		return false;
	}

	UObject* GetObject(const UObject* Obj, FName Name)
	{
		if (FObjectPropertyBase* Prop = CastField<FObjectPropertyBase>(FindProp(Obj, Name)))
		{
			return Prop->GetObjectPropertyValue_InContainer(Obj);
		}
		return nullptr;
	}

	bool GetObjectArray(const UObject* Obj, FName Name, TArray<UObject*>& Out)
	{
		Out.Reset();
		FArrayProperty* ArrayProp = CastField<FArrayProperty>(FindProp(Obj, Name));
		if (!ArrayProp)
		{
			return false;
		}
		FObjectPropertyBase* Inner = CastField<FObjectPropertyBase>(ArrayProp->Inner);
		if (!Inner)
		{
			return false;
		}
		FScriptArrayHelper_InContainer Helper(ArrayProp, Obj);
		for (int32 i = 0; i < Helper.Num(); ++i)
		{
			if (UObject* Element = Inner->GetObjectPropertyValue(Helper.GetRawPtr(i)))
			{
				Out.Add(Element);
			}
		}
		return true;
	}

	bool CallWithNumber(UObject* Obj, FName Function, double Value)
	{
		return CallFunction(Obj, Function, [Value](TArray<FProperty*, TInlineAllocator<8>>& Inputs, uint8* Params)
		{
			return Inputs.Num() > 0 && WriteNumber(Inputs[0], Params, Value);
		});
	}

	bool CallWithObject(UObject* Obj, FName Function, UObject* Value)
	{
		return CallFunction(Obj, Function, [Value](TArray<FProperty*, TInlineAllocator<8>>& Inputs, uint8* Params)
		{
			if (Inputs.Num() == 0)
			{
				return false;
			}
			if (FObjectPropertyBase* ObjProp = CastField<FObjectPropertyBase>(Inputs[0]))
			{
				if (Value && !Value->IsA(ObjProp->PropertyClass))
				{
					return false;
				}
				ObjProp->SetObjectPropertyValue_InContainer(Params, Value);
				return true;
			}
			return false;
		});
	}

	bool CallWithTextArgs(UObject* Obj, FName Function, const TArray<FString>& Args)
	{
		return CallFunction(Obj, Function, [&Args](TArray<FProperty*, TInlineAllocator<8>>& Inputs, uint8* Params)
		{
			for (int32 i = 0; i < Inputs.Num() && i < Args.Num(); ++i)
			{
				if (!Args[i].IsEmpty())
				{
					Inputs[i]->ImportText(*Args[i], Inputs[i]->ContainerPtrToValuePtr<void>(Params), PPF_None, nullptr);
				}
			}
			return true;
		});
	}

	bool CallWithFiller(UObject* Obj, FName Function, TFunctionRef<bool(const TArray<FProperty*>& Inputs, uint8* Params)> Fill)
	{
		return CallFunction(Obj, Function, [&Fill](TArray<FProperty*, TInlineAllocator<8>>& Inputs, uint8* Params)
		{
			TArray<FProperty*> Plain(Inputs);
			return Fill(Plain, Params);
		});
	}

	bool WriteParamNumber(FProperty* Param, uint8* Params, double Value)
	{
		return WriteNumber(Param, Params, Value);
	}

	bool WriteParamText(FProperty* Param, uint8* Params, const FText& Value)
	{
		if (FTextProperty* TextProp = CastField<FTextProperty>(Param))
		{
			TextProp->SetPropertyValue_InContainer(Params, Value);
			return true;
		}
		return false;
	}

	bool WriteParamObject(FProperty* Param, uint8* Params, UObject* Value)
	{
		FObjectPropertyBase* ObjProp = CastField<FObjectPropertyBase>(Param);
		if (!ObjProp || (Value && !Value->IsA(ObjProp->PropertyClass)))
		{
			return false;
		}
		ObjProp->SetObjectPropertyValue_InContainer(Params, Value);
		return true;
	}

	bool GetStructFloat(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, float& Out)
	{
		double V = 0.0;
		if (Row && ReadNumber(const_cast<FProperty*>(FindField(Struct, Field)), Row, V))
		{
			Out = (float)V;
			return true;
		}
		return false;
	}

	bool GetStructInt(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, int32& Out)
	{
		double V = 0.0;
		if (Row && ReadNumber(const_cast<FProperty*>(FindField(Struct, Field)), Row, V))
		{
			Out = (int32)V;
			return true;
		}
		return false;
	}

	bool GetStructByte(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, uint8& Out)
	{
		double V = 0.0;
		if (Row && ReadNumber(const_cast<FProperty*>(FindField(Struct, Field)), Row, V))
		{
			Out = (uint8)FMath::Clamp<int32>((int32)V, 0, 255);
			return true;
		}
		return false;
	}

	bool GetStructBool(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, bool& Out)
	{
		if (const FBoolProperty* Prop = CastField<FBoolProperty>(FindField(Struct, Field)))
		{
			if (Row)
			{
				Out = Prop->GetPropertyValue_InContainer(Row);
				return true;
			}
		}
		return false;
	}

	bool GetStructName(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, FName& Out)
	{
		if (const FNameProperty* Prop = CastField<FNameProperty>(FindField(Struct, Field)))
		{
			if (Row)
			{
				Out = Prop->GetPropertyValue_InContainer(Row);
				return true;
			}
		}
		return false;
	}

	bool GetStructText(const UScriptStruct* Struct, const void* Row, const TCHAR* Field, FText& Out)
	{
		if (const FTextProperty* Prop = CastField<FTextProperty>(FindField(Struct, Field)))
		{
			if (Row)
			{
				Out = Prop->GetPropertyValue_InContainer(Row);
				return true;
			}
		}
		return false;
	}

	FSoftObjectPath GetStructObjectPath(const UScriptStruct* Struct, const void* Row, const TCHAR* Field)
	{
		const FProperty* Prop = FindField(Struct, Field);
		if (!Prop || !Row)
		{
			return FSoftObjectPath();
		}
		if (const FSoftObjectProperty* Soft = CastField<FSoftObjectProperty>(Prop))
		{
			return Soft->GetPropertyValue_InContainer(Row).ToSoftObjectPath();
		}
		if (const FObjectPropertyBase* Hard = CastField<FObjectPropertyBase>(Prop))
		{
			return FSoftObjectPath(Hard->GetObjectPropertyValue_InContainer(Row));
		}
		return FSoftObjectPath();
	}

	UObject* GetStructObject(const UScriptStruct* Struct, const void* Row, const TCHAR* Field)
	{
		const FProperty* Prop = FindField(Struct, Field);
		if (!Prop || !Row)
		{
			return nullptr;
		}
		if (const FSoftObjectProperty* Soft = CastField<FSoftObjectProperty>(Prop))
		{
			const FSoftObjectPtr& Ptr = Soft->GetPropertyValue_InContainer(Row);
			return Ptr.IsNull() ? nullptr : Ptr.LoadSynchronous();
		}
		if (const FObjectPropertyBase* Hard = CastField<FObjectPropertyBase>(Prop))
		{
			return Hard->GetObjectPropertyValue_InContainer(Row);
		}
		return nullptr;
	}

	UDataTable* LoadTable(const FSoftObjectPath& Path)
	{
		if (!Path.IsValid())
		{
			return nullptr;
		}
		if (TWeakObjectPtr<UDataTable>* Cached = TableCache().Find(Path))
		{
			if (Cached->IsValid())
			{
				return Cached->Get();
			}
		}
		UDataTable* Table = Cast<UDataTable>(Path.TryLoad());
		if (!Table)
		{
			WarnOnce(Path.ToString(), FString::Printf(TEXT("DataTable '%s' could not be loaded."), *Path.ToString()));
			return nullptr;
		}
		// Item tables are small and used for the whole session; keep them resident.
		Table->AddToRoot();
		TableCache().Add(Path, Table);
		return Table;
	}

	const uint8* FindRow(const UDataTable* Table, FName RowName)
	{
		if (!Table || RowName.IsNone())
		{
			return nullptr;
		}
		return Table->FindRowUnchecked(RowName);
	}
}
