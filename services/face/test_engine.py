"""Real model smoke tests. These do not measure population-level accuracy."""
import io,unittest
from pathlib import Path
from PIL import Image,ImageEnhance
from app import embedding
class EngineTests(unittest.TestCase):
 def setUp(self):self.raw=(Path(__file__).parent/'testdata'/'portrait.png').read_bytes()
 def encode(self,image):
  out=io.BytesIO();image.save(out,format='PNG');return out.getvalue()
 def test_reference_and_exposure_variant(self):
  a=embedding(self.raw)
  with Image.open(io.BytesIO(self.raw)) as image:b=embedding(self.encode(ImageEnhance.Brightness(image).enhance(0.85)))
  self.assertEqual(len(a),128);self.assertGreater(sum(x*y for x,y in zip(a,b)),0.45)
 def test_close_phone_selfies_at_large_portrait_landscape_and_square_sizes(self):
  reference=embedding(self.raw)
  with Image.open(io.BytesIO(self.raw)) as image:
   close=image.crop((160,30,310,230));portrait=image.crop((140,0,330,300))
   for cropped,size in [(close,(960,1280)),(close,(1200,1600)),(portrait,(1013,1600)),(image,(1600,1600))]:
    with self.subTest(size=size):
     encoded=io.BytesIO();cropped.resize(size).save(encoded,format='JPEG',quality=90)
     values=embedding(encoded.getvalue())
     self.assertGreater(sum(x*y for x,y in zip(reference,values)),0.45)
 def test_two_close_faces_in_large_phone_frame(self):
  with Image.open(io.BytesIO(self.raw)) as image:
   head=image.crop((140,0,330,300)).resize((640,1011));pair=Image.new('RGB',(1280,1011));pair.paste(head,(0,0));pair.paste(head,(640,0))
   with self.assertRaisesRegex(ValueError,'несколько лиц'):embedding(self.encode(pair))
 def test_no_face(self):
  with self.assertRaises(ValueError):embedding(self.encode(Image.new('RGB',(512,512),'white')))
 def test_two_faces(self):
  with Image.open(io.BytesIO(self.raw)) as image:
   pair=Image.new('RGB',(image.width*2,image.height));pair.paste(image,(0,0));pair.paste(image,(image.width,0))
   with self.assertRaises(ValueError):embedding(self.encode(pair))
 def test_invalid_or_oversize(self):
  for raw in [b'',b'invalid',b'x'*(2*1024*1024+1)]:
   with self.assertRaises(Exception):embedding(raw)
if __name__=='__main__':unittest.main()
