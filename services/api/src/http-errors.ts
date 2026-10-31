import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Catch()
export class HttpErrors implements ExceptionFilter {
  catch(exception:any,host:ArgumentsHost) {
    const request=host.switchToHttp().getRequest(),response=host.switchToHttp().getResponse();
    const status=exception instanceof HttpException?exception.getStatus():exception?.code==='23505'?409:exception?.type==='entity.too.large'?413:500;
    const provided=exception instanceof HttpException?(exception.getResponse() as any)?.error:undefined;
    const error=provided??{code:status===409?'STATE_CONFLICT':status===413?'FILE_TOO_LARGE':status===500?'INTERNAL_ERROR':'VALIDATION_ERROR',message:status===500?'Внутренняя ошибка сервиса':status===409?'Объект уже существует или изменился':'Некорректный запрос',details:{},retryable:status>=500};
    const retryAfter=error.details?.retry_after_seconds;
    if(status===429&&Number.isSafeInteger(retryAfter)&&retryAfter>=1&&retryAfter<=86400)response.setHeader('Retry-After',String(retryAfter));
    response.setHeader('Cache-Control','no-store');response.status(status).json({error:{...error,request_id:request.joba_request_id??randomUUID()}});
  }
}
