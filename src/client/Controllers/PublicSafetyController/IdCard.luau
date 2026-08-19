--!strict
return function(PublicSafetyController)
	function PublicSafetyController:_showCard(card: any)
		local police = card.CredentialType == "Police"
		if police then
			-- The warrant-card Tool has its own fitted SurfaceGui and is visible in
			-- the officer's hand. The generic licence overlay does not share its
			-- proportions, so displaying both caused text to overflow the asset.
			self.card.Visible = false
			return
		end
		self.card.BackgroundColor3 = if police
			then Color3.fromRGB(234, 237, 242)
			else Color3.fromRGB(225, 217, 195)
		self.band.BackgroundColor3 = if police
			then Color3.fromRGB(20, 46, 73)
			else Color3.fromRGB(40, 66, 82)
		self.cardTitle.Text = if police
			then card.ForceName
			else "ROLEPLAY DRIVING LICENCE · UNITED KINGDOM"
		self.cardSubtitle.Text = if police then "POLICE WARRANT CARD" else "FICTIONAL PHOTOCARD"
		self.avatar.Image = card.AvatarImage or ""
		self.cardName.Text = string.upper(card.FullName)
		self.cardDob.Text = if police
			then "RANK  ·  " .. tostring(card.Rank or "POLICE OFFICER")
			else "DATE OF BIRTH  ·  " .. card.DateOfBirth
		self.cardNumber.Text = if police
			then "WARRANT NUMBER  ·  " .. tostring(card.WarrantNumber or "")
			else "DRIVER NUMBER  ·  " .. card.DocumentNumber
		self.validity.Text = if police
			then "PRESENTED BY THE NAMED OFFICER"
			else string.format("ISSUED  %s    ·    VALID TO  %s", card.Issued, card.ValidTo)
		self.card.Visible = true
		task.delay(8, function()
			if self.card then
				self.card.Visible = false
			end
		end)
	end
end
