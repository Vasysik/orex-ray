from PIL import Image, ImageFilter

SRC = r'C:\Users\vasia\Documents\Projects\OrexRay\tool\shots\redmi-rot.png'
DST = r'C:\Users\vasia\Documents\Projects\OrexRay\tool\shots\redmi-land-clean.png'

im = Image.open(SRC).convert('RGB')

# Profile name and host lines inside the profile card (original 2560x1600).
boxes = [
    (1700, 590, 2010, 655),   # "VReality-BigBob"
    (1700, 650, 1970, 700),   # "v.m.vasys.ru:443"
]
for box in boxes:
    region = im.crop(box).filter(ImageFilter.GaussianBlur(18))
    im.paste(region, box)

im.save(DST)
print('saved', DST)
