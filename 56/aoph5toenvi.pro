; ENVI 5.6 / IDL 8.8 compatibility update for NEON AOP HDF5 files.
; Based on the BSD-licensed NEON-AOP-H5toENVI extension.

function _aopIsHash, value
  compile_opt idl2, hidden
  typeName = typename(value)
  return, (typeName eq 'HASH') || (typeName eq 'ORDEREDHASH')
end

function _aopObjectPath, node
  compile_opt idl2, hidden
  if (~_aopIsHash(node)) then return, ''
  if (~node.HasKey('_NAME')) then return, ''
  name = string(node['_NAME'])
  path = node.HasKey('_PATH') ? string(node['_PATH']) : '/'
  if (path eq '/') then return, '/' + name
  if (strmid(path, path.StrLen()-1, 1) eq '/') then return, path + name
  return, path + '/' + name
end

function _aopPrettyName, name
  compile_opt idl2, hidden
  upperName = strupcase(name)
  case upperName of
    'REFLECTANCE_DATA': return, 'Reflectance'
    'SMOOTH_SURFACE_ELEVATION': return, 'Surface Elevation'
    else: return, strjoin(strsplit(name, '_', /EXTRACT), ' ')
  endcase
end

function _aopAssetPath, e, filename
  compile_opt idl2, hidden
  sep = path_sep()
  ; During source debugging, the current directory is usually this 56 folder.
  if (file_test(filename)) then return, file_expand_path(filename)
  pathMatch = file_which(filename)
  if ((pathMatch ne '') && file_test(pathMatch)) then return, pathMatch

  candidates = [ $ 
    e.ROOT_DIR + 'extensions' + sep + filename, $ 
    e.ROOT_DIR + 'extensions' + sep + 'NEON' + sep + filename]
  foreach candidate, candidates do begin
    if (file_test(candidate)) then return, candidate
  endforeach
  return, ''
end

function _aopNeonTreeFinder56, rootID
  compile_opt idl2, hidden
  if (~widget_info(rootID, /VALID_ID)) then return, 0L
  queue = list(rootID)
  visited = list(rootID)
  while (~queue.IsEmpty()) do begin
    current = queue.Remove(0)
    if (~widget_info(current, /VALID_ID)) then continue
    if (widget_info(current, /TYPE) eq 11) then begin
      widget_control, current, GET_VALUE=value
      if (strupcase(string(value)) eq 'NEON') then return, current
    endif
    children = widget_info(current, /ALL_CHILDREN)
    foreach child, children do begin
      if (widget_info(child, /VALID_ID) && (visited.Count(child) eq 0)) then begin
        visited.Add, child
        queue.Add, child
      endif
    endforeach
  endwhile
  return, 0L
end

pro _setNEONBitmap56, id, userData
  compile_opt idl2, hidden
  e = ENVI(/CURRENT)
  if (~obj_valid(e)) then return
  if (~widget_info(e.WIDGET_ID, /VALID_ID)) then return
  treeID = _aopNeonTreeFinder56(e.WIDGET_ID)
  if (~widget_info(treeID, /VALID_ID)) then return
  imageFile = _aopAssetPath(e, 'smallneonlogo.png')
  if (imageFile eq '') then return

  image = read_png(imageFile)
  image = congrid(image, 3, 16, 16)
  red = reform(image[0, *, *])
  green = reform(image[1, *, *])
  blue = reform(image[2, *, *])
  icon = bytarr(16, 16, 3)
  icon[*, *, 0] = red
  icon[*, *, 1] = green
  icon[*, *, 2] = blue
  widget_control, treeID, SET_TREE_BITMAP=icon
  children = widget_info(treeID, /ALL_CHILDREN)
  foreach child, children do begin
    if (widget_info(child, /VALID_ID) && (widget_info(child, /TYPE) eq 11)) then $ 
      widget_control, child, SET_TREE_BITMAP=icon
  endforeach
end

pro _aopCollectDatasets, node, output
  compile_opt idl2, hidden
  if (~_aopIsHash(node)) then return

  if (node.HasKey('_TYPE')) then begin
    if (strupcase(string(node['_TYPE'])) eq 'DATASET') then begin
      if (node.HasKey('_NDIMENSIONS') && node.HasKey('_DIMENSIONS')) then begin
        ndims = long(node['_NDIMENSIONS'])
        dims = node['_DIMENSIONS']
        isRaster = (ndims eq 3) || ((ndims eq 2) && $ 
          (dims[0] gt 1) && (dims[1] gt 1))
        if (isRaster) then begin
          item = hash(/FOLD_CASE)
          item['NAME'] = string(node['_NAME'])
          item['LABEL'] = _aopPrettyName(string(node['_NAME']))
          item['PATH'] = _aopObjectPath(node)
          output.Add, item
        endif
      endif
      return
    endif
  endif

  keys = node.Keys()
  foreach key, keys do begin
    if (strmid(string(key), 0, 1) eq '_') then continue
    child = node[key]
    if (_aopIsHash(child)) then _aopCollectDatasets, child, output
  endforeach
end

function _aopFindDataset, root, request
  compile_opt idl2, hidden
  datasets = list()
  _aopCollectDatasets, root, datasets
  wanted = strupcase(string(request))
  if (wanted eq 'REFLECTANCE') then wanted = 'REFLECTANCE_DATA'

  foreach item, datasets do begin
    name = strupcase(item['NAME'])
    path = strupcase(item['PATH'])
    if ((name eq wanted) || (path eq wanted) || $ 
        (path eq '/' + wanted)) then return, string(item['PATH'])
  endforeach
  return, ''
end

pro _aopDatasetChooser_event, ev
  compile_opt idl2, hidden
  common AOPH5_CHOOSER_COMMON, chooserSelected, chooserCancelled
  wBase = ev.TOP
  widget_control, wBase, GET_UVALUE=state
  uName = widget_info(ev.ID, /UNAME)

  case uName of
    'OK': begin
      datasetPaths = state['DATASET_PATHS']
      checks = state['CHECKS']
      datasetCount = n_elements(datasetPaths)
      selectedPaths = strarr(datasetCount)
      selectedCount = 0L
      for i = 0L, datasetCount-1L do begin
        checkID = checks[i]
        if (widget_info(checkID, /BUTTON_SET)) then begin
          selectedPaths[selectedCount] = datasetPaths[i]
          selectedCount++
        endif
      endfor
      ; Keep the result outside the widget UVALUE. In IDL 8.8, object
      ; references nested in a Hash UVALUE can become invalid as soon as the
      ; top-level widget is destroyed.
      if (selectedCount gt 0) then $ 
        chooserSelected = selectedPaths[0:selectedCount-1L] $ 
      else chooserSelected = !null
      chooserCancelled = 0B
      widget_control, wBase, /DESTROY
    end
    'CANCEL': begin
      chooserCancelled = 1B
      widget_control, wBase, /DESTROY
    end
    else:
  endcase
end

function _aopDatasetChooser, h5
  compile_opt idl2, hidden
  common AOPH5_CHOOSER_COMMON, chooserSelected, chooserCancelled
  e = ENVI(/CURRENT)
  if (~obj_valid(e)) then return, list()

  discoveredDatasets = list()
  _aopCollectDatasets, h5, discoveredDatasets
  if (discoveredDatasets.Count() eq 0) then begin
    void = dialog_message( $ 
      'No two- or three-dimensional raster datasets were found in this HDF5 file.', $ 
      /ERROR)
    return, list()
  endif

  ; HDF5 member order is not guaranteed. Put the main hyperspectral cube first
  ; so it is always visible even on small displays.
  datasets = list()
  foreach item, discoveredDatasets do begin
    if (strupcase(item['NAME']) eq 'REFLECTANCE_DATA') then datasets.Add, item
  endforeach
  foreach item, discoveredDatasets do begin
    if (strupcase(item['NAME']) ne 'REFLECTANCE_DATA') then datasets.Add, item
  endforeach

  ; ENVI 5.6 can return a stale WIDGET_ID after extensions are recompiled in
  ; a running session. A modal base must have a valid group leader, so use a
  ; small hidden fallback leader when the ENVI top-level widget is stale.
  wENVI = e.WIDGET_ID
  ownsLeader = 0B
  if (~widget_info(wENVI, /VALID_ID)) then begin
    wENVI = widget_base(TITLE='NEON AOP H5 Reader', /COLUMN, MAP=0)
    widget_control, wENVI, /REALIZE
    ownsLeader = 1B
  endif

  wBase = widget_base(/MODAL, GROUP_LEADER=wENVI, /COLUMN, $ 
    TITLE='Select the desired data set(s):', XSIZE=470)
  wNEONLogo = widget_draw(wBase, XSIZE=415, YSIZE=120, RETAIN=2)
  wHint = widget_label(wBase, $ 
    VALUE='Select one or more raster datasets:', /ALIGN_LEFT, XSIZE=450)
  wScroll = widget_base(wBase, /COLUMN, /NONEXCLUSIVE, /SCROLL, $ 
    X_SCROLL_SIZE=450, Y_SCROLL_SIZE=430)

  datasetCount = datasets.Count()
  checks = lonarr(datasetCount)
  datasetPaths = strarr(datasetCount)
  foreach item, datasets, i do begin
    label = item['LABEL']
    datasetPaths[i] = string(item['PATH'])
    check = widget_button(wScroll, VALUE=label, UNAME='DATASET_' + string(i), $ 
      TOOLTIP=item['PATH'], /ALIGN_LEFT)
    checks[i] = check
  endforeach

  ; Reflectance is the normal default and avoids accidentally opening the
  ; three-band Weather Quality Indicator dataset.
  foreach item, datasets, i do begin
    if (strupcase(item['NAME']) eq 'REFLECTANCE_DATA') then $ 
      widget_control, checks[i], /SET_BUTTON
  endforeach

  wButtons = widget_base(wBase, /ROW, /ALIGN_CENTER)
  wOK = widget_button(wButtons, VALUE='OK', UNAME='OK', XSIZE=210)
  wCancel = widget_button(wButtons, VALUE='Cancel', UNAME='CANCEL', XSIZE=210)

  state = hash(/FOLD_CASE)
  state['DATASET_PATHS'] = datasetPaths
  state['CHECKS'] = checks
  chooserSelected = !null
  chooserCancelled = 1B
  widget_control, wBase, SET_UVALUE=state
  widget_control, wBase, /REALIZE

  ; Restore the original NEON banner. The dialog still works if the image was
  ; not installed; in that case a plain-text fallback is drawn.
  imageFile = _aopAssetPath(e, 'NEON-Logo.png')
  widget_control, wNEONLogo, GET_VALUE=drawID
  wset, drawID
  if (imageFile ne '') then begin
    image = read_png(imageFile)
    tv, image, TRUE=1
  endif else begin
    erase, 255
    xyouts, 0.08, 0.45, 'NEON Airborne Observation Platform', /NORMAL, $ 
      COLOR=0
  endelse
  xmanager, '_aopDatasetChooser', wBase

  if (ownsLeader && widget_info(wENVI, /VALID_ID)) then $ 
    widget_control, wENVI, /DESTROY
  if (chooserCancelled) then return, !null
  return, chooserSelected
end

pro AOPH5toENVI_extensions_init
  compile_opt idl2
  e = ENVI(/CURRENT)
  if (~obj_valid(e)) then return
  e.AddExtension, 'NEON AOP H5 Reader (ENVI 5.6)', 'AOPH5toENVI', PATH='NEON'
  e.AddCustomReader, 'NEON AOP H5 Reader (ENVI 5.6)', 'AOPH5toENVI', PATH='NEON'
  timerID = Timer.Set(3.0, '_setNEONBitmap56')
end

function OpenAOPH5, filename, DATASET_NAME=datasetName
  compile_opt idl2
  AOPH5toENVI, FILENAMES=filename, DATASET_NAME=datasetName, $ 
    _GETRASTERS=rasters, /HEADLESS
  if (n_elements(rasters) eq 0) then return, !null
  return, rasters[0]
end

function _aopOpenRaster56, e, file, datasetPath, spatialRef, metadata, $ 
  USED_FALLBACK=usedFallback
  compile_opt idl2, hidden
  usedFallback = 0B

  ; Validate every object immediately before passing it to ENVI 5.6. Some
  ; builds invalidate override objects created while a modal widget is active.
  validSpatialRef = isa(spatialRef) ? obj_valid(spatialRef) : 0B
  validMetadata = isa(metadata) ? obj_valid(metadata) : 0B

  CATCH, openErr
  if (openErr ne 0) then begin
    ; Cancel this local handler before retrying, so a genuine failure from the
    ; plain HDF5 reader propagates to the caller's error handler.
    CATCH, /CANCEL
    usedFallback = 1B
    return, e.OpenRaster(file, DATASET_NAME=datasetPath, INTERLEAVE='bip')
  endif

  if (validSpatialRef && validMetadata) then begin
    return, e.OpenRaster(file, DATASET_NAME=datasetPath, INTERLEAVE='bip', $ 
      SPATIALREF_OVERRIDE=spatialRef, METADATA_OVERRIDE=metadata)
  endif
  if (validSpatialRef) then begin
    return, e.OpenRaster(file, DATASET_NAME=datasetPath, INTERLEAVE='bip', $ 
      SPATIALREF_OVERRIDE=spatialRef)
  endif
  if (validMetadata) then begin
    return, e.OpenRaster(file, DATASET_NAME=datasetPath, INTERLEAVE='bip', $ 
      METADATA_OVERRIDE=metadata)
  endif

  usedFallback = 1B
  return, e.OpenRaster(file, DATASET_NAME=datasetPath, INTERLEAVE='bip')
end

pro AOPH5toENVI, none, FILENAMES=filenames, DATASET_NAME=datasetName, $ 
  _GETRASTERS=rasters, HEADLESS=headless
  compile_opt idl2

  stage = 'initialization'
  CATCH, err
  if (err ne 0) then begin
    msg = !error_state.msg
    CATCH, /CANCEL
    void = dialog_message('NEON AOP H5 Reader (' + stage + '): ' + msg, /ERROR)
    return
  endif

  if (!version.RELEASE lt 8.8) then begin
    void = dialog_message('This build requires ENVI 5.6 / IDL 8.8 or newer.', /ERROR)
    return
  endif

  e = ENVI(/CURRENT)
  if (~obj_valid(e)) then return

  if (n_elements(filenames) eq 0) then $ 
    files = dialog_pickfile(FILTER='*.h5', /MULTIPLE_FILES) $ 
  else files = filenames[*]
  if (n_elements(files) eq 0) then return
  firstFile = files[0]
  if (firstFile.StrLen() eq 0) then return

  rasters = []
  foreach file, files do begin
    if (file.StrLen() eq 0) then continue
    stage = 'reading HDF5 structure'
    h5 = h5_parse(file, /ORDEREDHASH)

    selectedPaths = !null
    if (n_elements(datasetName) eq 0) then begin
      stage = 'dataset selection'
      selectedPaths = _aopDatasetChooser(h5)
    endif else begin
      stage = 'finding requested dataset'
      requests = datasetName[*]
      foundPaths = strarr(n_elements(requests))
      foundCount = 0L
      foreach request, requests do begin
        datasetPath = _aopFindDataset(h5, request)
        if (datasetPath ne '') then begin
          foundPaths[foundCount] = datasetPath
          foundCount++
        endif
      endforeach
      if (foundCount gt 0) then selectedPaths = foundPaths[0:foundCount-1L]
    endelse

    if (~isa(selectedPaths)) then continue
    foreach datasetPath, selectedPaths do begin
      ; Reacquire the current ENVI object after the modal widget closes.
      e = ENVI(/CURRENT)
      if (~obj_valid(e)) then message, 'The current ENVI session is no longer valid.'
      stage = 'creating spatial reference'
      spatialRef = AOPh5MetadataFactory.CreateSpatialRef(h5)
      stage = 'creating raster metadata'
      metadata = AOPh5MetadataFactory.CreateMetadata(h5, datasetPath)
      stage = 'opening raster ' + datasetPath
      raster = _aopOpenRaster56(e, file, datasetPath, spatialRef, metadata, $ 
        USED_FALLBACK=usedFallback)
      rasters = [rasters, raster]

      if (~keyword_set(headless)) then begin
        stage = 'displaying raster'
        view = e.GetView()
        layer = view.CreateLayer(raster)
        if (usedFallback) then begin
          void = dialog_message( $ 
            'The raster was opened with the ENVI 5.6 generic HDF5 reader. ' + $ 
            'The metadata override objects were rejected, but all source bands are available.', $ 
            /INFORMATION)
        endif
      endif
    endforeach
  endforeach
end
