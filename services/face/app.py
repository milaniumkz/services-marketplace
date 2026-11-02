"""Local one-face descriptor extraction. No liveness or anti-spoofing is performed."""
import io,json,threading,warnings
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
import cv2,numpy as np
from PIL import Image,ImageOps
cv2.setNumThreads(1);Image.MAX_IMAGE_PIXELS=16000000
warnings.simplefilter('error',Image.DecompressionBombWarning)
ROOT=Path(__file__).parent/'models';LOCK=threading.Lock();MODEL='opencv-sface-2021dec-yunet-2023mar-v1'
DETECTOR=cv2.FaceDetectorYN.create(str(ROOT/'face_detection_yunet_2023mar.onnx'),'',(320,320),0.9,0.3,5000)
RECOGNIZER=cv2.FaceRecognizerSF.create(str(ROOT/'face_recognition_sface_2021dec.onnx'),'')
def embedding(raw):
 if not raw or len(raw)>2*1024*1024:raise ValueError('Размер снимка должен быть не более 2 МБ.')
 with Image.open(io.BytesIO(raw)) as image:
  if image.format not in ('JPEG','PNG') or image.width*image.height>16000000:raise ValueError('Нужен снимок JPG или PNG до 16 мегапикселей.')
  image=ImageOps.exif_transpose(image).convert('RGB');image.thumbnail((1600,1600));frame=cv2.cvtColor(np.asarray(image),cv2.COLOR_RGB2BGR)
 if min(frame.shape[:2])<112:raise ValueError('Поднесите камеру ближе и сделайте более чёткий снимок.')
 DETECTOR.setInputSize((frame.shape[1],frame.shape[0]));_,faces=DETECTOR.detect(frame)
 if faces is None or len(faces)!=1:raise ValueError('В рамке должно быть ровно одно хорошо освещённое лицо.')
 if min(faces[0][2:4])<80:raise ValueError('Поднесите лицо ближе к камере.')
 aligned=RECOGNIZER.alignCrop(frame,faces[0]);v=RECOGNIZER.feature(aligned).flatten().astype(float);norm=float(np.linalg.norm(v))
 if len(v)!=128 or not np.isfinite(v).all() or norm<=0:raise ValueError('Не удалось обработать лицо. Повторите снимок.')
 return (v/norm).tolist()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def respond(self,status,data):
  body=json.dumps(data,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def do_GET(self):self.respond(200 if self.path=='/health' else 404,{'ready':True,'model':MODEL,'liveness':False})
 def do_POST(self):
  if self.path!='/embedding':return self.respond(404,{'error':'Not found'})
  self.connection.settimeout(20)
  try:length=int(self.headers.get('Content-Length','0'))
  except ValueError:return self.respond(422,{'error':'Некорректный снимок.'})
  if length<=0 or length>2*1024*1024:return self.respond(413,{'error':'Размер снимка должен быть не более 2 МБ.'})
  if not LOCK.acquire(timeout=1):return self.respond(503,{'error':'Обработка занята. Повторите чуть позже.'})
  try:self.respond(200,{'embedding':embedding(self.rfile.read(length)),'model':MODEL})
  except (ValueError,Image.DecompressionBombError,Image.DecompressionBombWarning) as e:self.respond(422,{'error':str(e)})
  except Exception:self.respond(422,{'error':'Не удалось прочитать лицо. Повторите снимок.'})
  finally:LOCK.release()
if __name__=='__main__':ThreadingHTTPServer(('0.0.0.0',8080),Handler).serve_forever()
