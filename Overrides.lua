-- Manual achievement mapping for dungeons that neither LibSets nor the name matching can resolve.
-- Run "/dledger debug" to see which dungeon rows have no achievement.
-- Key: the dungeon name as shown in the finder; case, punctuation and grammar markers are ignored.
-- Value: achievement ids, either field optional.
--   normal  = achievement used for the NORMAL header row
--   veteran = achievement used for the VETERAN header row
DungeoneersLedger = DungeoneersLedger or {}
DungeoneersLedger.overrides =
{
    -- ["fungal grotto i"] = { normal = 0, veteran = 0 },
}
