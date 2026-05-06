# AWS Lambda container image. The .NET API invokes this Lambda directly via
# the AWS SDK (no API Gateway, no public ALB) — IAM is the auth boundary.

FROM public.ecr.aws/lambda/python:3.12

COPY wisecat/requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

COPY wisecat/ ${LAMBDA_TASK_ROOT}/wisecat/

ARG GIT_HASH=dev
ARG BUILD_TIME=unknown
ENV GIT_HASH=${GIT_HASH}
ENV BUILD_TIME=${BUILD_TIME}

CMD [ "wisecat.lambda_handler.handler" ]
