# ENVI 5.6 兼容版安装与测试

本目录中的两个 `.pro` 文件针对 ENVI 5.6 / IDL 8.8 和当前 NEON AOP HDF5
层级进行了修改。原项目根目录及 `52`、`53` 文件夹保持不变。

## 先在 IDL 控制台测试

将 IDL 当前目录切换到本目录，然后依次执行：

```idl
.compile aoph5metadatafactory__define.pro
.compile aoph5toenvi.pro

e = ENVI()
file = 'G:\NEON_refl-surf-dir-ortho-mosaic\NEON.D17.SOAP.DP3.30006.001.2019-06.basic.20260820T080444Z.RELEASE-2026\NEON_D17_SOAP_DP3_305000_4098000_reflectance.h5'
raster = OpenAOPH5(file, DATASET_NAME='REFLECTANCE')
view = e.GetView()
layer = view.CreateLayer(raster)
```

`REFLECTANCE` 会自动映射到新版文件中的 `Reflectance_Data`。如果不提供
`DATASET_NAME`，会显示数据集选择窗口，并默认勾选 Reflectance：

```idl
AOPH5toENVI, FILENAMES=file
```

## 生成并安装 `.sav` 扩展

1. 单独启动 IDL 8.8 Workbench，依次打开并编译
   `aoph5metadatafactory__define.pro` 和 `aoph5toenvi.pro`。
2. 在 IDL 控制台执行（输出路径可自行修改）：

   ```idl
   save, /routines, filename='D:\temp\aoph5toenvi56.sav'
   ```

3. 退出 ENVI，备份并移走原先安装的 `aoph5toenvi.sav`，防止旧版过程覆盖新版过程。
4. 将新生成的 `aoph5toenvi56.sav`、`NEON-Logo.png` 和
   `smallneonlogo.png` 一起复制到原插件所在的 ENVI 5.6 `extensions`
   目录。两个 PNG 分别用于选择窗口横幅和 Extensions 树图标；缺失时不会影响数据读取。
5. 重启 ENVI，从 Extensions 菜单运行 `NEON AOP H5 Reader (ENVI 5.6)`。

如果扩展菜单与旧版重名，请确保 extensions 目录中只保留一个版本的
`AOPH5toENVI_extensions_init`。

## 当前 NEON DP3 拼接影像的数据说明

- `Reflectance_Data` 在 HDF5 中标注为 BSQ，但 IDL 读取后的维度顺序为
  `[band, sample, line]`，因此传给 ENVI 时必须使用 `INTERLEAVE='bip'`。
- 反射率为整数存储，实际反射率等于原始值除以 10000；无效值为 -9999。
- Slope 和 Aspect 是度，比例因子为 1。
- `to-sensor_zenith_angle` 和 `to-sensor_azimuth_angle` 是逐像元角度栅格，单位为度。
- DP3 tile 可能由多个航线拼接而成，因此太阳方位角和太阳天顶角不是唯一值。
  插件会把所有航线的太阳方位角、天顶角以及换算后的太阳高度角写入反射率元数据，
  不会错误地把第一条航线的角度当作整幅影像的统一角度。
- 该批次文件将若干 byte 辅助栅格的拼接区无效值实际写成了 241，插件已将 241
  设为这些栅格的 ENVI Data Ignore Value。
- 源文件把 `Smooth_Surface_Elevation` 的单位和说明误写成了太阳天顶角；插件显示时修正为米。
- 源文件把 `Illumination_Factor` 的说明误写成 Sensor Azimuth Angle；插件显示时修正为
  地形入射角余弦乘以 100。
