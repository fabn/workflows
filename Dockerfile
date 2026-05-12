# Dummy image to use in testing
FROM ealen/echo-server:latest
# Do nothing but listen on port 3000
ENV PORT=3000

ARG APP_REVISION
ARG BRANCH
ARG SHA

# Set envs from build args
ENV APP_REVISION=${APP_REVISION}
ENV BRANCH=${BRANCH}
ENV SHA=${SHA}

RUN "echo" "APP_REVISION=${APP_REVISION}" >> /etc/environment
