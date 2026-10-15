# The Earth maps: sources, licences, credits

The rocky planet in the Space theme is drawn from these four maps (shader:
`GraphStyleShaders.rockBody`; loader: `Features/Notes/GraphEarth.swift`).
All four are NASA imagery or data. They were made from the downloads below by
`tools/earth_textures.py`, which says exactly how (`python3 -I
tools/earth_textures.py --day ... --clouds ... --lights ... --water ...`); the
downloads themselves are not kept in the repository.

All maps are equirectangular: longitude -180 at the left edge to +180 at the
right, latitude +90 at the top.

| File | What it holds | Made from |
|---|---|---|
| `earth-day.jpg` | 4096 x 2048, true colour, sRGB | Blue Marble: Next Generation, July 2004, with topography |
| `earth-clouds.jpg` | 4096 x 2048, cloud cover (0 clear, 255 overcast) | The Blue Marble (2002), cloud layer |
| `earth-lights.jpg` | 2048 x 1024, lights at night, sRGB-encoded | Black Marble 2016, grayscale |
| `earth-water.png` | 2048 x 1024, open water (0 land, 255 water) | GPM IMERG land-sea mask |

## Sources

### `earth-day.jpg`: Blue Marble: Next Generation (July 2004, with topography)

- Page: https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-topography/
- File: https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-topography/july/world.topo.200407.3x5400x2700.jpg
  (5400 x 2700, SHA-256 `85a24885616097b5e06532b7d8e30fa5d749a782e70ea55971dd8539a0899206`)
- Credit: **NASA Earth Observatory**. The project page asks: "Anyone using or
  republishing Blue Marble: Next Generation please credit 'NASA Earth
  Observatory.'" Produced by Reto Stöckli, NASA Earth Observatory (NASA
  Goddard Space Flight Center).
- Processing: resized to 4096 x 2048 with a Lanczos filter in linear light;
  JPEG quality 92, no chroma subsampling.

### `earth-clouds.jpg`: The Blue Marble (2002), clouds

- Page: https://science.nasa.gov/earth/earth-observatory/the-blue-marble-true-color-global-imagery-at-1km-resolution/
- File: https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/cloud_combined_8192.tif
  (8192 x 4096, SHA-256 `d137775d8966ab8d443fd5126dc6e7ad72072bc1ed50555c5818d221735daf0f`)
- Credit: NASA Goddard Space Flight Center. Image by Reto Stöckli (land
  surface, shallow water, clouds); enhancements by Robert Simmon (ocean
  colour, compositing, 3D globes, animation).
- Processing: grey value taken as cover, resized to 4096 x 2048 (Lanczos);
  JPEG quality 90.

### `earth-lights.jpg`: Black Marble 2016 (Earth at Night), grayscale, 3 km

- Page: https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/
- File: https://assets.science.nasa.gov/content/dam/science/esd/eo/images/imagerecords/144000/144897/BlackMarble_2016_3km_gray.jpg
  (13500 x 6750, SHA-256 `3fbc8aae3529dc1ebfcf3aa9361bd3dfc11d19950a6af6d8ed2df61bd8b0134d`)
- Credit: NASA Earth Observatory images by Joshua Stevens, using Suomi NPP
  VIIRS data from Miguel Román, NASA's Goddard Space Flight Center.
- Processing: tagged sRGB, so taken to linear light, resized to 2048 x 1024
  (Lanczos: a town keeps its total glow), back to sRGB; JPEG quality 92.

### `earth-water.png`: GPM IMERG land-sea mask

- Page: https://gpm.nasa.gov/data/directory/imerg-land-sea-mask-netcdf
- File: https://gpm.nasa.gov/sites/default/files/downloads/IMERG_land_sea_mask.nc.gz
  (NetCDF, 0.1 degree grid, percent water; gzip SHA-256
  `dfc6245b74304230da7818beca08407daaa1982402b12a64bdde950004189bb4`)
- Credit: the IMERG land-sea mask, provided by NASA's Global Precipitation
  Measurement (GPM) mission and the Precipitation Processing System, NASA
  Goddard Space Flight Center.
- Processing: rows turned north first, the repeated columns at -0.05 and
  360.05 degrees dropped and the rest rolled to start at -180; percent to
  0...1; resized to 2048 x 1024 (Lanczos); 8-bit PNG.

## Licences

- **NASA imagery** (the day, cloud and night maps): "NASA content - images,
  audio, video, related media and files used in the rendition of
  3-dimensional models, such as texture maps and polygon data in any format -
  generally are not subject to copyright in the United States." Commercial
  use is allowed as long as it does not "explicitly or implicitly convey
  NASA's endorsement of commercial goods or services", and NASA's emblems and
  logos are not used. NASA Images and Media Usage Guidelines:
  https://www.nasa.gov/nasa-brand-center/images-and-media/
- **GPM data** (the water mask): "GPM and TRMM data are freely available";
  the data set source should be acknowledged when the data are used. GPM Data
  Usage Policy: https://gpm.nasa.gov/data/policy

Nothing here implies that NASA endorses the app. Where the app credits its
imagery, it says: "Earth imagery: NASA Earth Observatory (Blue Marble: Next
Generation, Black Marble); clouds: NASA Goddard Space Flight Center; water
mask: NASA GPM."
