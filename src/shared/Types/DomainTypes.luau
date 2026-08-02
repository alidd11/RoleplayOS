--!strict

export type Response<T> = {
	Success: boolean,
	Code: string,
	Message: string,
	Data: T?,
	RequestId: string,
}
export type AccessResult = {
	Allowed: boolean,
	ReasonCode: string,
	Message: string,
	Metadata: { [string]: any },
}
export type AccessRule = {
	AccessType: "Public"
		| "Gamepass"
		| "Application"
		| "Group"
		| "Rank"
		| "Qualification"
		| "Department"
		| "Whitelist"
		| "Staff"
		| "Combined",
	Id: string?,
	GamepassId: number?,
	GroupLinkId: string?,
	MinimumGroupRank: number?,
	DepartmentId: string?,
	QualificationId: string?,
	MinimumRank: number?,
	DisplayWhenLocked: boolean?,
	Rules: { AccessRule }?,
	Match: "All" | "Any"?,
}
export type GamepassRule = { Id: string, GamepassId: number, Name: string, Description: string }
export type ApplicationRecord = {
	ApplicationId: string,
	FormId: string,
	Status: string,
	Answers: { [string]: string },
	SubmittedAt: number?,
	UpdatedAt: number,
	ApplicantMessage: string?,
}
export type Qualification = {
	QualificationId: string,
	AwardedAt: number,
	AwardedBy: number?,
	ExpiresAt: number?,
}
export type EmploymentRecord = {
	EmploymentId: string,
	JobId: string,
	Grade: number,
	Experience: number,
	Warnings: { string },
	StartedAt: number,
	EndedAt: number?,
}
export type PlayerSettings = {
	InterfaceScale: "Small" | "Standard" | "Large",
	InterfaceMotion: boolean,
	HighContrast: boolean,
	ReducedEffects: boolean,
	CameraShake: boolean,
	ShowHints: boolean,
}
export type ProgressionSummary = {
	Level: number,
	TotalXP: number,
	CurrentLevelXP: number,
	RequiredLevelXP: number,
	Progress: number,
	AtMaximumLevel: boolean,
	Tracks: { [string]: any },
}
export type ShiftRecord = {
	ShiftId: string,
	EmploymentId: string,
	StartedAt: number,
	EndedAt: number?,
	TaskIds: { string },
	Earnings: number,
}
export type Transaction = {
	TransactionId: string,
	CharacterId: string,
	Amount: number,
	Direction: "Credit" | "Debit",
	ReasonCode: string,
	Description: string,
	Timestamp: number,
	RelatedEntityId: string?,
	Metadata: { [string]: any },
	Result: string,
}
export type BankAccount = { Balance: number, Cash: number, Transactions: { Transaction } }
export type VehicleDefinition = {
	Id: string,
	Name: string,
	Price: number,
	ModelName: string,
	Colours: { string },
	Access: AccessRule,
}
export type OwnedVehicle = {
	VehicleId: string,
	OwnerCharacterId: string,
	DefinitionId: string,
	Registration: string,
	Colour: string,
	Mileage: number,
	Fuel: number,
	Condition: number,
	Insured: boolean,
	Taxed: boolean,
	StoredGarageId: string,
}
export type PropertyDefinition = {
	Id: string,
	Name: string,
	PurchasePrice: number?,
	RentPrice: number?,
	InteriorTemplate: string,
	FurnitureCapacity: number,
	GarageCapacity: number,
}
export type PropertyHolding = {
	PropertyId: string,
	CharacterId: string,
	HoldingType: "Owned" | "Rented",
	StartedAt: number,
	RentDueAt: number?,
	AccessCharacterIds: { string },
}
export type FurnitureDefinition = {
	Id: string,
	Name: string,
	Category: string,
	Price: number,
	Bounds: { number },
	Access: AccessRule,
}
export type OwnedFurnitureItem = { ItemId: string, DefinitionId: string, Quantity: number }
export type SerialisedTransform = { Position: { number }, Rotation: { number } }
export type FurniturePlacement = {
	PlacementId: string,
	ItemId: string,
	PropertyId: string,
	Transform: SerialisedTransform,
}
export type BusinessRecord = {
	BusinessId: string,
	DefinitionId: string,
	OwnerCharacterId: string,
	ManagerCharacterIds: { string },
	EmployeeCharacterIds: { string },
	Balance: number,
}
export type InventoryItem = {
	ItemId: string,
	DefinitionId: string,
	Quantity: number,
	Metadata: { [string]: any },
}
export type MDTPersonRecord = {
	CharacterId: string,
	FullName: string,
	DateOfBirth: string,
	Licences: { string },
	Flags: { string },
}
export type MDTVehicleRecord = {
	VehicleId: string,
	Registration: string,
	DefinitionId: string,
	OwnerCharacterId: string,
	Flags: { string },
}
export type Incident = {
	IncidentId: string,
	Title: string,
	Status: string,
	PersonIds: { string },
	VehicleIds: { string },
	Notes: { string },
	CreatedAt: number,
	ClosedAt: number?,
}
export type DispatchCall = {
	CallId: string,
	Priority: string,
	Summary: string,
	Location: string,
	UnitIds: { string },
	Status: string,
	CreatedAt: number,
}
export type ActiveUnit = {
	UnitId: string,
	UserId: number,
	Callsign: string,
	DepartmentId: string,
	DivisionId: string?,
	StationId: string,
	Status: string,
}
export type Station = { Id: string, Name: string, DepartmentIds: { string }, SpawnIds: { string } }
export type SpawnDefinition = {
	Id: string,
	StationId: string,
	TeamName: string,
	RoleIds: { string },
	DepartmentIds: { string },
}
export type Role = {
	Id: string,
	Name: string,
	TeamName: string,
	DepartmentId: string?,
	Access: AccessRule,
	LoadoutId: string?,
	UniformId: string?,
}
export type Department = { Id: string, Name: string, Ranks: { string }, RoleIds: { string } }
export type Loadout = { Id: string, ToolNames: { string } }
export type Uniform = { Id: string, ShirtTemplate: string, TrousersTemplate: string }
export type SpawnRequest = {
	CharacterId: string?,
	DutyProfileId: string?,
	RoleId: string,
	StationId: string,
	SpawnId: string,
}
export type AuditLogEntry = {
	ActorUserId: number,
	CharacterId: string?,
	Action: string,
	Target: string,
	Timestamp: number,
	ServerJobId: string,
	RequestId: string?,
	Metadata: { [string]: any },
}
export type CommunityRole = { Id: string, Priority: number, Permissions: { string } }
export type CommunityMembership = {
	CommunityId: string,
	RoleId: string,
	Status: "Invited" | "Pending" | "Active" | "Suspended" | "Banned",
	JoinedAt: number?,
	UpdatedAt: number,
}
export type CommunityRecord = {
	CommunityId: string,
	Name: string,
	OwnerUserId: number,
	RobloxGroup: {
		GroupId: number,
		Name: string,
		EmblemUrl: string?,
		OwnerUserId: number,
	}?,
	TemplateId: string,
	CreatedAt: number,
	UpdatedAt: number,
	Policies: { [string]: any },
	Branding: { PrimaryColour: string?, LogoAssetId: number? },
	Members: { [string]: CommunityMembership },
	Version: number,
}
export type DutyProfile = {
	ProfileId: string,
	DepartmentId: string,
	Rank: number,
	QualificationIds: { string },
	Callsign: string?,
}
export type CharacterIdentity = { FirstName: string, LastName: string, DateOfBirth: string }
export type CivilianCharacter = {
	CharacterId: string,
	Identity: CharacterIdentity,
	Appearance: { [string]: any },
	Economy: BankAccount,
	Employment: { EmploymentRecord },
	Vehicles: { OwnedVehicle },
	Properties: { PropertyHolding },
	FurnitureInventory: { OwnedFurnitureItem },
	Inventory: { InventoryItem },
	Licences: { string },
	CriminalRecord: { string },
	MedicalRecord: { string },
	Progression: { [string]: any },
	CreatedAt: number,
	LastPlayedAt: number,
}
export type PlayerProfile = {
	SchemaVersion: number,
	UserId: number,
	Settings: PlayerSettings,
	CharacterSlots: { string },
	Characters: { [string]: CivilianCharacter },
	DutyProfiles: { [string]: DutyProfile },
	Whitelists: { [string]: boolean },
	Applications: { ApplicationRecord },
	Qualifications: { [string]: Qualification },
	GamepassCache: { [string]: boolean },
	Communities: { [string]: CommunityMembership },
	AuditMetadata: { [string]: any },
}

return nil
