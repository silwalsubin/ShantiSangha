# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ShantiSangha.sln .
COPY ShantiSangha.Api/ShantiSangha.Api.csproj ShantiSangha.Api/
COPY ShantiSangha.Core/ShantiSangha.Core.csproj ShantiSangha.Core/
COPY ShantiSangha.Infrastructure/ShantiSangha.Infrastructure.csproj ShantiSangha.Infrastructure/

RUN dotnet restore

COPY . .
RUN dotnet publish ShantiSangha.Api/ShantiSangha.Api.csproj \
    -c Release \
    -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Non-root user for security
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "ShantiSangha.Api.dll"]
