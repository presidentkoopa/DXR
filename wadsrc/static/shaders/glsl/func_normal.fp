
void SetupMaterial(inout Material material)
{
	SetMaterialProps(material, GetAffineTexCoord(vTexCoord.st));
}
