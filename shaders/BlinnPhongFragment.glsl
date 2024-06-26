#version 330 core
struct DirectionalLight {
    //                      offsets:
    vec3 lightColor;     // 0
    float intensity;     // 12
    vec3 direction;      // 16
    float ambientIntensity; // 28
}; // size 32

struct PointLight {
    vec3 lightColor; // 0
    float intensity; // 12
    vec3 pos; // 16
    float constant; // 28
    float linear; // 32
    float quadratic; // 36
    float ambientIntensity; // 40
}; // size 48

struct Spotlight {
    vec3 lightColor; // 0
    float intensity; // 12
    vec3 pos; // 16
    float innerCutOff; // 28
    vec3 direction; // 32
    float outerCutOff; // 44
    float ambientIntensity; // 48
}; // size 64
#define MAX_POINT_LIGHTS 50
#define MAX_SPOT_LIGHTS 50
layout (std140) uniform Lights {
    vec3 viewerPos; // 0
    float hasDirLight; // 12
    int pointLightsCount; // 16
    int spotLightsCount; // 20
    PointLight pointLights[MAX_POINT_LIGHTS]; // 32
    Spotlight spotLights[MAX_POINT_LIGHTS]; // 32+48*50=2432
    DirectionalLight dirLight; // 2432+64*50 = 5632
}; // size 5632 + 32 = 5664

layout (location = 0) out vec4 FragColor;
layout (location = 1) out vec4 BrightColor;

in vec2 TexCoord;
in vec3 Normal;
in vec3 FragPos;
in mat3 TBN;

struct Material {
    sampler2D texture_diffuse0;
    sampler2D texture_specular0;
    sampler2D texture_normal0;
    sampler2D texture_emission0;
    bool useNormalMap;
    bool useEmissionMap;
    vec4 blendColor;
    float shininess;
    float emissionStrength;
};

uniform Material material;

const float kPi = 3.14159265;


vec3 calcDiffuseColor(inout vec3 normal, vec3 lightDir, inout vec4 diffuseMaterialColor) {
    float diff = max(dot(normal, -lightDir), 0.0);
    return diff*diffuseMaterialColor.rgb;
}

vec3 calcSpecularColor(inout vec4 specularMaterialColor, inout vec3 normal, vec3 lightDir, inout vec3 viewDir) {
    vec3 halfwayDir = normalize(lightDir + viewDir);
    float kEnergyConservation = ( 8.0 + material.shininess ) / ( 8.0 * kPi );
    float spec = pow(max(dot(normal, halfwayDir), 0.0), material.shininess)*kEnergyConservation;
    return specularMaterialColor.rgb * spec*sign(max(dot(normal, -lightDir), 0.0));
}

vec3 calcPhongColor( vec3 lightColor, inout float ambientIntensity, inout vec3 normal, vec3 lightDir, inout vec3 viewDir, inout vec4 diffuseMaterialColor, inout vec4 specularMaterialColor) {
    vec3 ambient = diffuseMaterialColor.rgb*ambientIntensity;
    vec3 diffuse = calcDiffuseColor(normal, lightDir, diffuseMaterialColor);
    vec3 specular = calcSpecularColor(specularMaterialColor, normal, lightDir, viewDir);
    return (ambient+diffuse+specular)*lightColor;
}

vec3 calcDirLight(DirectionalLight light, inout vec3 normal, inout vec3 viewDir, inout vec4 diffuseMaterialColor, inout vec4 specularMaterialColor) {
    vec3 lightDir = normalize(-light.direction);
    vec3 phongColor = calcPhongColor(light.lightColor, light.ambientIntensity, normal, lightDir, viewDir, diffuseMaterialColor, specularMaterialColor);
    return hasDirLight*phongColor*light.intensity;
}

vec3 calcPointLight(PointLight light, inout vec3 normal, inout vec3 viewDir, inout vec4 diffuseMaterialColor, inout vec4 specularMaterialColor) {
    vec3 lightDir = FragPos - light.pos;
    float distance    = length(lightDir);
    lightDir = normalize(lightDir);
    float attenuation = 1.0 / (light.constant + light.linear * distance +
                               light.quadratic * (distance * distance));
    vec3 phongColor = calcPhongColor(light.lightColor, light.ambientIntensity, normal, lightDir, viewDir, diffuseMaterialColor, specularMaterialColor);
    return phongColor*light.intensity*attenuation;
}

vec3 calcSpotlight(Spotlight light, inout vec3 normal, inout vec3 viewDir, inout vec4 diffuseMaterialColor, inout vec4 specularMaterialColor) {
    vec3 lightDir = FragPos - light.pos;
    float distance    = length(lightDir);
    lightDir = normalize(lightDir);
    float theta = dot(lightDir, normalize(light.direction));
    float epsilon = light.innerCutOff - light.outerCutOff;
    float intensity = clamp((theta - light.outerCutOff) / epsilon, 0.0, 1.0);
    float distanceIntensity = clamp(2-distance*0.2, 0.0, 1.0);
    
    vec3 phongColor = calcPhongColor(light.lightColor, light.ambientIntensity, normal, lightDir, viewDir, diffuseMaterialColor, specularMaterialColor);
    
    return phongColor*light.intensity*intensity*distanceIntensity;
}

void main()
{
    vec3 norm = Normal;
    if (material.useNormalMap) {
        norm = texture(material.texture_normal0, TexCoord).rgb;
        norm = normalize(norm*2.0-1.0);
        norm = TBN*norm;
    }
    vec3 viewDir = normalize(viewerPos - FragPos);
    
    vec4 fragmentDiffuseColor = texture(material.texture_diffuse0, TexCoord);
    
    vec4 fragmentSpecularColor = texture(material.texture_specular0, TexCoord);
    
    
    vec4 result = vec4(calcDirLight(dirLight, norm, viewDir, fragmentDiffuseColor, fragmentSpecularColor), fragmentDiffuseColor.w);
    for (int i = 0; i < pointLightsCount; i++) {
        result.rgb += calcPointLight(pointLights[i], norm, viewDir, fragmentDiffuseColor, fragmentSpecularColor);
    }
    for (int i = 0; i < spotLightsCount; i++) {
        result.rgb += calcSpotlight(spotLights[i], norm, viewDir, fragmentDiffuseColor, fragmentSpecularColor);
    }
    FragColor = result*material.blendColor;
    FragColor.rgb += texture(material.texture_emission0, TexCoord).rgb*int(material.useEmissionMap)*material.emissionStrength;

    float brightness = dot(FragColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    if(brightness > 1.0)
        BrightColor = vec4(FragColor.rgb, 1.0);
    else
        BrightColor = vec4(0.0, 0.0, 0.0, 1.0);
}
