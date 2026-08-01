# Vehicles

Dealership catalogues refer to configured vehicle IDs. Purchase revalidates catalogue membership and access, debits the configured price, then creates a GUID ownership record and generated registration. Ownership, colour, mileage, fuel, condition, insurance, tax and garage are persisted per character.

Spawning checks active character ownership and clones only a configured ServerStorage model. Final spawn-volume collision checks, fuel simulation, transfer and resale escrow remain future work. Finance agreements are outside v0.1.
