

; ENVI 5.6 metadata adapter for current NEON AOP HDF5 products.

function _aopMetaIsHash, value
  compile_opt idl2, hidden
  typeName = typename(value)
  return, (typeName eq 'HASH') || (typeName eq 'ORDEREDHASH')
end

function _aopMetaObjectPath, node
  compile_opt idl2, hidden
  if (~_aopMetaIsHash(node)) then return, ''
  name = string(node['_NAME'])
  path = node.HasKey('_PATH') ? string(node['_PATH']) : '/'
  if (path eq '/') then return, '/' + name
  if (strmid(path, path.StrLen()-1, 1) eq '/') then return, path + name
  return, path + '/' + name
end

function _aopFindNodeByName, node, wanted
  compile_opt idl2, hidden
  if (~_aopMetaIsHash(node)) then return, !null

  if (node.HasKey('_NAME')) then begin
    if (strupcase(string(node['_NAME'])) eq strupcase(string(wanted))) then $ 
      return, node
  endif

  keys = node.Keys()
  foreach key, keys do begin
    if (strmid(string(key), 0, 1) eq '_') then continue
    child = node[key]
    if (_aopMetaIsHash(child)) then begin
      found = _aopFindNodeByName(child, wanted)
      if (isa(found)) then return, found
    endif
  endforeach
  return, !null
end

function _aopFindNodeByPath, node, wantedPath
  compile_opt idl2, hidden
  if (~_aopMetaIsHash(node)) then return, !null
  if (node.HasKey('_NAME')) then begin
    if (strupcase(_aopMetaObjectPath(node)) eq strupcase(string(wantedPath))) then $ 
      return, node
  endif
  keys = node.Keys()
  foreach key, keys do begin
    if (strmid(string(key), 0, 1) eq '_') then continue
    child = node[key]
    if (_aopMetaIsHash(child)) then begin
      found = _aopFindNodeByPath(child, wantedPath)
      if (isa(found)) then return, found
    endif
  endforeach
  return, !null
end

pro _aopCollectNodesByName, node, wanted, output
  compile_opt idl2, hidden
  if (~_aopMetaIsHash(node)) then return
  if (node.HasKey('_NAME')) then begin
    if (strupcase(string(node['_NAME'])) eq strupcase(string(wanted))) then $ 
      output.Add, node
  endif
  keys = node.Keys()
  foreach key, keys do begin
    if (strmid(string(key), 0, 1) eq '_') then continue
    child = node[key]
    if (_aopMetaIsHash(child)) then _aopCollectNodesByName, child, wanted, output
  endforeach
end

function _aopNodeData, root, node
  compile_opt idl2, hidden
  if (~isa(node)) then return, !null
  if (node.HasKey('_TYPE')) then begin
    if (strupcase(string(node['_TYPE'])) eq 'DATASET') then $ 
      return, h5_getdata(root['_FILE'], _aopMetaObjectPath(node))
  endif
  if (node.HasKey('_DATA')) then return, node['_DATA']
  return, !null
end

function _aopAttributeData, node, names
  compile_opt idl2, hidden
  if (~_aopMetaIsHash(node)) then return, !null
  keys = node.Keys()
  foreach requested, names do begin
    foreach key, keys do begin
      if (strupcase(string(key)) eq strupcase(string(requested))) then begin
        attr = node[key]
        if (_aopMetaIsHash(attr) && attr.HasKey('_DATA')) then return, attr['_DATA']
      endif
    endforeach
  endforeach
  return, !null
end

function AOPh5MetadataFactory::Init, _EXTRA=extra
  compile_opt idl2
  return, 1
end

pro AOPh5MetadataFactory::Cleanup
  compile_opt idl2
end

pro AOPh5MetadataFactory::GetProperty, _REF_EXTRA=extra
  compile_opt idl2
end

pro AOPh5MetadataFactory::SetProperty, _EXTRA=extra
  compile_opt idl2
end

function AOPh5MetadataFactory::CreateSpatialRef, h5
  compile_opt static, idl2
  mapNode = _aopFindNodeByName(h5, 'Map_Info')
  coordNode = _aopFindNodeByName(h5, 'Coordinate_System_String')
  if ((~isa(mapNode)) || (~isa(coordNode))) then return, !null

  mapText = string((_aopNodeData(h5, mapNode))[0])
  coordSysString = string((_aopNodeData(h5, coordNode))[0])
  mapStuff = strtrim(strsplit(mapText, ',', /EXTRACT), 2)
  if (n_elements(mapStuff) lt 7) then return, !null

  ps = double(mapStuff[5:6])
  tm = double(mapStuff[3:4])
  rotation = !null
  foreach field, mapStuff do begin
    if (strmatch(strlowcase(field), '*rotation*')) then begin
      parts = strsplit(field, '=', /EXTRACT)
      if (n_elements(parts) gt 1) then rotation = double(parts[-1])
    endif
  endforeach

  if (~isa(rotation)) then begin
    return, ENVIStandardRasterSpatialRef(COORD_SYS_STR=coordSysString, $ 
      PIXEL_SIZE=ps, TIE_POINT_MAP=tm, TIE_POINT_PIXEL=[0D, 0D])
  endif
  return, ENVIStandardRasterSpatialRef(COORD_SYS_STR=coordSysString, $ 
    PIXEL_SIZE=ps, TIE_POINT_MAP=tm, TIE_POINT_PIXEL=[0D, 0D], $ 
    ROTATION=rotation)
end

function AOPh5MetadataFactory::CreateMetadata, h5, dataSetPath
  compile_opt static, idl2
  metadata = ENVIRasterMetadata()
  node = _aopFindNodeByPath(h5, dataSetPath)
  if (~isa(node)) then return, metadata

  nameUpper = strupcase(string(node['_NAME']))
  if (nameUpper eq 'REFLECTANCE_DATA') then begin
    waveNode = _aopFindNodeByName(h5, 'Wavelength')
    fwhmNode = _aopFindNodeByName(h5, 'FWHM')
    if (isa(waveNode)) then begin
      metadata.AddItem, 'wavelength', _aopNodeData(h5, waveNode)
      waveUnits = _aopAttributeData(waveNode, ['Units', 'Unit'])
      if (isa(waveUnits)) then metadata.AddItem, 'wavelength units', waveUnits
    endif
    if (isa(fwhmNode)) then $ 
      metadata.AddItem, 'fwhm', _aopNodeData(h5, fwhmNode)
    AOPh5MetadataFactory._AddSolarMetadata, h5, metadata
  endif

  AOPh5MetadataFactory._AddCommonRasterMetadata, node, metadata
  if ((nameUpper eq 'DARK_DENSE_VEGETATION_CLASSIFICATION') || $ 
      (nameUpper eq 'HAZE_CLOUD_WATER_MAP')) then $ 
    AOPh5MetadataFactory._AddClassificationMetadata, node, metadata
  return, metadata
end

pro AOPh5MetadataFactory::_AddCommonRasterMetadata, node, metadata
  compile_opt static, idl2
  nameUpper = strupcase(string(node['_NAME']))
  scale = _aopAttributeData(node, ['Scale_Factor'])
  if (isa(scale)) then metadata.AddItem, 'reflectance scale factor', scale
  description = _aopAttributeData(node, ['Description'])
  if (nameUpper eq 'SMOOTH_SURFACE_ELEVATION') then $ 
    description = 'Smooth surface elevation used as input to ATCOR.'
  if (nameUpper eq 'ILLUMINATION_FACTOR') then $ 
    description = $ 
      'Terrain illumination factor: cosine of solar incidence angle times 100.'
  if (isa(description)) then metadata.AddItem, 'description', description
  ignore = _aopAttributeData(node, ['Data_Ignore_Value'])
  ; Several current DP3 mosaics store byte rasters with 241 as the tile-fill
  ; value even when the inherited flight-line attribute says -9999 (or 0).
  ; Without this correction ENVI treats the fill as valid data.
  byteFillNames = ['CAST_SHADOW', 'DARK_DENSE_VEGETATION_CLASSIFICATION', $ 
    'HAZE_CLOUD_WATER_MAP', 'ILLUMINATION_FACTOR', 'SKY_VIEW_FACTOR', $ 
    'VISIBILITY_INDEX_MAP']
  if (total(nameUpper eq byteFillNames) gt 0) then ignore = 241B
  if (isa(ignore)) then metadata.AddItem, 'data ignore value', ignore
  units = _aopAttributeData(node, ['Units', 'Unit'])
  ; Correct two known metadata-label errors in this NEON mosaic generation.
  if (nameUpper eq 'SMOOTH_SURFACE_ELEVATION') then units = 'meters'
  if (nameUpper eq 'ILLUMINATION_FACTOR') then units = 'percent (cosine x 100)'
  if (isa(units)) then metadata.AddItem, 'data units', units
end

pro AOPh5MetadataFactory::_AddSolarMetadata, h5, metadata
  compile_opt static, idl2
  azNodes = list()
  zenNodes = list()
  _aopCollectNodesByName, h5, 'Solar_Azimuth_Angle', azNodes
  _aopCollectNodesByName, h5, 'Solar_Zenith_Angle', zenNodes
  count = azNodes.Count() < zenNodes.Count()
  if (count le 0) then return

  azimuth = dblarr(count)
  zenith = dblarr(count)
  flightLines = strarr(count)
  for i = 0L, count-1L do begin
    ; IDL 8.8 cannot chain a List subscript directly into a Hash subscript.
    azNode = azNodes[i]
    zenNode = zenNodes[i]
    azData = _aopNodeData(h5, azNode)
    zenData = _aopNodeData(h5, zenNode)
    azimuth[i] = double(azData[0])
    zenith[i] = double(zenData[0])
    parentPath = string(azNode['_PATH'])
    parts = strsplit(parentPath, '/', /EXTRACT)
    flightLines[i] = parts[-1]
  endfor

  ; A DP3 tile may contain several contributing flight lines, each with a
  ; different solar geometry. Preserve every value instead of silently using
  ; whichever log happens to be found first.
  metadata.AddItem, 'NEON solar-angle flight lines', flightLines
  metadata.AddItem, 'NEON solar azimuth angles', azimuth
  metadata.AddItem, 'NEON solar zenith angles', zenith
  metadata.AddItem, 'NEON solar elevation angles', 90D - zenith
  if (count eq 1) then begin
    metadata.AddItem, 'sun azimuth', azimuth[0]
    metadata.AddItem, 'sun elevation', 90D - zenith[0]
  endif
end

pro AOPh5MetadataFactory::_AddClassificationMetadata, node, metadata
  compile_opt static, idl2
  classNamesText = _aopAttributeData(node, ['Class_Names'])
  classLookupText = _aopAttributeData(node, ['Class_Lookup'])
  if (isa(classNamesText)) then begin
    text = string(classNamesText)
    delimiter = strmatch(text, '*;*') ? ';' : ','
    classNames = strtrim(strsplit(text, delimiter, /EXTRACT), 2)
    metadata.AddItem, 'classes', n_elements(classNames)
    metadata.AddItem, 'class names', classNames
  endif
  if (isa(classLookupText)) then begin
    lookupType = size(classLookupText, /TYPE)
    if (lookupType eq 7) then $ 
      lookup = byte(fix(strsplit(string(classLookupText), ',', /EXTRACT))) $ 
    else lookup = byte(fix(classLookupText))
    if ((n_elements(lookup) mod 3) eq 0) then $ 
      metadata.AddItem, 'class lookup', reform(lookup, 3, n_elements(lookup)/3)
  endif
  bandNames = _aopAttributeData(node, ['Band_Names'])
  if (isa(bandNames)) then metadata.AddItem, 'band names', [string(bandNames)]
end

pro AOPh5MetadataFactory__define
  compile_opt idl2
  void = {AOPh5MetadataFactory, inherits IDL_Object}
end
