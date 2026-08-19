# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ShantiSangha.sln .
COPY ShantiSangha.Api/ShantiSangha.Api.csproj ShantiSangha.Api/
COPY ShantiSangha.Shared/ShantiSangha.Shared.csproj ShantiSangha.Shared/
COPY ShantiSangha.Identity/ShantiSangha.Identity.csproj ShantiSangha.Identity/
COPY ShantiSangha.Reminders/ShantiSangha.Reminders.csproj ShantiSangha.Reminders/
COPY ShantiSangha.Chat/ShantiSangha.Chat.csproj ShantiSangha.Chat/
COPY ShantiSangha.Journal/ShantiSangha.Journal.csproj ShantiSangha.Journal/
COPY ShantiSangha.Memory/ShantiSangha.Memory.csproj ShantiSangha.Memory/
COPY ShantiSangha.Wellness/ShantiSangha.Wellness.csproj ShantiSangha.Wellness/
COPY ShantiSangha.Friends/ShantiSangha.Friends.csproj ShantiSangha.Friends/
COPY ShantiSangha.Notifications/ShantiSangha.Notifications.csproj ShantiSangha.Notifications/

# Restore only the API project (transitively restores all referenced projects).
# This avoids needing to copy the test project's csproj into the build stage.
RUN dotnet restore ShantiSangha.Api/ShantiSangha.Api.csproj

COPY . .
RUN dotnet publish ShantiSangha.Api/ShantiSangha.Api.csproj \
    -c Release \
    -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Install curl for ECS health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Non-root user for security
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

COPY --from=build /app/publish .

ARG GIT_HASH=dev
ARG BUILD_TIME=unknown
ENV GIT_HASH=${GIT_HASH}
ENV BUILD_TIME=${BUILD_TIME}
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "ShantiSangha.Api.dll"]
