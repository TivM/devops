# Stage 1: build
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

COPY pom.xml .
COPY src ./src

RUN mvn -B package -DskipTests -q

# Stage 2: run
FROM eclipse-temurin:17-jre
WORKDIR /app

# Default: connect to host "db" (docker-compose service)
ENV SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/taskmanager
ENV SPRING_DATASOURCE_USERNAME=postgres
ENV SPRING_DATASOURCE_PASSWORD=postgres

COPY --from=build /app/target/*.jar app.jar
EXPOSE 3001
ENTRYPOINT ["java", "-jar", "app.jar"]
