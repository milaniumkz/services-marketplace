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
def face_overlap(a,b):
 left=max(a[0],b[0]);top=max(a[1],b[1]);right=min(a[0]+a[2],b[0]+b[2]);bottom=min(a[1]+a[3],b[1]+b[3])
 intersection=max(0,right-left)*max(0,bottom-top)
 return intersection/max(1,a[2]*a[3]+b[2]*b[3]-intersection)
def detect_faces(frame):
 # YuNet misses close-up faces on large phone frames. Detect at two training-
 # sized scales, then map landmarks back to the full image for SFace alignment.
 height,width=frame.shape[:2];found=[];sizes=set()
 for side in (640,320):
  scale=min(1,side/max(width,height));size=(max(1,round(width*scale)),max(1,round(height*scale)))
  if size in sizes:continue
  sizes.add(size);small=cv2.resize(frame,size,interpolation=cv2.INTER_AREA) if size!=(width,height) else frame
  DETECTOR.setInputSize(size);_,faces=DETECTOR.detect(small)
  if faces is None:continue
  for face in faces:
   candidate=face.copy();candidate[[0,2,4,6,8,10,12]]*=width/size[0];candidate[[1,3,5,7,9,11,13]]*=height/size[1]
   duplicate=next((i for i,old in enumerate(found) if face_overlap(candidate,old)>0.4),None)
   if duplicate is None:found.append(candidate)
   elif candidate[-1]>found[duplicate][-1]:found[duplicate]=candidate
 return found
def embedding(raw):
 if not raw or len(raw)>2*1024*1024:raise ValueError('Размер снимка должен быть не более 2 МБ.')
 with Image.open(io.BytesIO(raw)) as image:
  if image.format not in ('JPEG','PNG') or image.width*image.height>16000000:raise ValueError('Нужен снимок JPG или PNG до 16 мегапикселей.')
  image=ImageOps.exif_transpose(image).convert('RGB');image.thumbnail((1600,1600));frame=cv2.cvtColor(np.asarray(image),cv2.COLOR_RGB2BGR)
 if min(frame.shape[:2])<112:raise ValueError('Поднесите камеру ближе и сделайте более чёткий снимок.')
 faces=detect_faces(frame)
 if not faces:raise ValueError('Не удалось найти лицо на снимке. Посмотрите прямо в камеру, держите лицо целиком внутри рамки и повторите снимок.')
 if len(faces)>1:raise ValueError('На снимке найдено несколько лиц. Останьтесь в кадре один и повторите снимок.')
 if min(faces[0][2:4])<80:raise ValueError('Поднесите лицо ближе к камере.')
 aligned=RECOGNIZER.alignCrop(frame,faces[0]);v=RECOGNIZER.feature(aligned).flatten().astype(float);norm=float(np.linalg.norm(v))
 if len(v)!=128 or not np.isfinite(v).all() or norm<=0:raise ValueError('Не удалось обработать лицо. Повторите снимок.')
 return (v/norm).tolist()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def respond(self,status,data):
  body=json.dumps(data,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def do_GET(self):self.respond(200 if self.path=='/health' else 404,{'ready':True,'model':MODEL,'liveness':False,'detector_scales':[640,320]})
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
