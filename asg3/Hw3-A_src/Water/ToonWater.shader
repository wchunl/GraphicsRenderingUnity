﻿// Credits go to Roystan
// Modified code from https://roystan.net/articles/toon-water.html

Shader "Custom/ToonWater"
{
    Properties
    {
		// What color the water will sample when the surface below is shallow.
		_DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)

		// What color the water will sample when the surface below is at its deepest.
		_DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)

		// Maximum distance the surface below the water will affect the color gradient.
		_DepthMaxDistance("Depth Maximum Distance", Float) = 1

		// Color to render the foam generated by objects intersecting the surface.
		_FoamColor("Foam Color", Color) = (1,1,1,1)

		// Noise texture used to generate waves.
		_SurfaceNoise("Surface Noise", 2D) = "white" {}

		// Speed, in UVs per second the noise will scroll. Only the xy components are used.
		_SurfaceNoiseScroll("Surface Noise Scroll Amount", Vector) = (0.03, 0.03, 0, 0)

		// Values in the noise texture above this cutoff are rendered on the surface.
		_SurfaceNoiseCutoff("Surface Noise Cutoff", Range(0, 1)) = 0.777

		// Red and green channels of this texture are used to offset the
		// noise texture to create distortion in the waves.
		_SurfaceDistortion("Surface Distortion", 2D) = "white" {}	

		// Multiplies the distortion by this value.
		_SurfaceDistortionAmount("Surface Distortion Amount", Range(0, 1)) = 0.27

		// Control the distance that surfaces below the water will contribute
		// to foam being rendered.
		_FoamMaxDistance("Foam Maximum Distance", Float) = 0.4
		_FoamMinDistance("Foam Minimum Distance", Float) = 0.04		

		// Cubemap for reflection
		_Cube ("Cubemap", CUBE) = "" {}

		// Water Transparency
		_WaterTransparency("Water Transparency", Float) = 0.5
    }
    SubShader
    {
		Tags
		{
			"Queue" = "Transparent"
		}


        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
             
            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };
            

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 normalInWorldCoords : NORMAL;
                float3 vertexInWorldCoords : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                
                o.vertexInWorldCoords = mul(unity_ObjectToWorld, v.vertex); //Vertex position in WORLD coords
                o.normalInWorldCoords = UnityObjectToWorldNormal(v.normal); //Normal 
                
                o.vertex = UnityObjectToClipPos(v.vertex);
                
                return o;
            }
            
            samplerCUBE _Cube;
            
            fixed4 frag (v2f i) : SV_Target
            {
            
             float3 P = i.vertexInWorldCoords.xyz;
             
             //get normalized incident ray (from camera to vertex)
             float3 vIncident = normalize(P - _WorldSpaceCameraPos);
             
             //reflect that ray around the normal using built-in HLSL command
             float3 vReflect = reflect( vIncident, i.normalInWorldCoords );
             
             
             //use the reflect ray to sample the skybox
             float4 reflectColor = texCUBE( _Cube, vReflect );
             
             //refract the incident ray through the surface using built-in HLSL command
             float3 vRefractRed = refract( vIncident, i.normalInWorldCoords, 0.1 );
             float3 vRefractGreen = refract( vIncident, i.normalInWorldCoords, 0.4 );
             float3 vRefractBlue = refract( vIncident, i.normalInWorldCoords, 0.7 );
             
             float4 refractColorRed = texCUBE( _Cube, float3( vRefractRed ) );
             float4 refractColorGreen = texCUBE( _Cube, float3( vRefractGreen ) );
             float4 refractColorBlue = texCUBE( _Cube, float3( vRefractBlue ) );
             float4 refractColor = float4(refractColorRed.r, refractColorGreen.g, refractColorBlue.b, 1.0);
             
             
             return float4(lerp(reflectColor, refractColor, 0.5).rgb, 0.5);
                
                
            }
      
            ENDCG
        }

		Pass
        {
			// Transparent "normal" blending.
			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off

            CGPROGRAM
			#define SMOOTHSTEP_AA 0.01

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

			// Blends two colors using the same algorithm that our shader is using
			// to blend with the screen. This is usually called "normal blending",
			// and is similar to how software like Photoshop blends two layers.
			float4 alphaBlend(float4 top, float4 bottom)
			{
				float3 color = (top.rgb * top.a) + (bottom.rgb * (1 - top.a));
				float alpha = top.a + bottom.a * (1 - top.a);

				return float4(color, alpha);
			}

            struct appdata
            {
                float4 vertex : POSITION;
				float4 uv : TEXCOORD0;
				float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;	
				float2 noiseUV : TEXCOORD0;
				float2 distortUV : TEXCOORD1;
				float4 screenPosition : TEXCOORD2;
				float3 viewNormal : NORMAL;
            };

			sampler2D _SurfaceNoise;
			float4 _SurfaceNoise_ST;

			sampler2D _SurfaceDistortion;
			float4 _SurfaceDistortion_ST;

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);
				o.screenPosition = ComputeScreenPos(o.vertex);
				o.distortUV = TRANSFORM_TEX(v.uv, _SurfaceDistortion);
				o.noiseUV = TRANSFORM_TEX(v.uv, _SurfaceNoise);
				o.viewNormal = COMPUTE_VIEW_NORMAL;

                return o;
            }

			float4 _DepthGradientShallow;
			float4 _DepthGradientDeep;
			float4 _FoamColor;

			float _DepthMaxDistance;
			float _FoamMaxDistance;
			float _FoamMinDistance;
			float _SurfaceNoiseCutoff;
			float _SurfaceDistortionAmount;
			float _WaterTransparency;

			float2 _SurfaceNoiseScroll;

			sampler2D _CameraDepthTexture;
			sampler2D _CameraNormalsTexture;

            float4 frag (v2f i) : SV_Target
            {
				// Retrieve the current depth value of the surface behind the
				// pixel we are currently rendering.
				float existingDepth01 = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPosition)).r;
				// Convert the depth from non-linear 0...1 range to linear
				// depth, in Unity units.
				float existingDepthLinear = LinearEyeDepth(existingDepth01);

				// Difference, in Unity units, between the water's surface and the object behind it.
				float depthDifference = existingDepthLinear - i.screenPosition.w;

				// Calculate the color of the water based on the depth using our two gradient colors.
				float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
				float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);
				
				// Retrieve the view-space normal of the surface behind the
				// pixel we are currently rendering.
				float3 existingNormal = tex2Dproj(_CameraNormalsTexture, UNITY_PROJ_COORD(i.screenPosition));
				
				// Modulate the amount of foam we display based on the difference
				// between the normals of our water surface and the object behind it.
				// Larger differences allow for extra foam to attempt to keep the overall
				// amount consistent.
				float3 normalDot = saturate(dot(existingNormal, i.viewNormal));
				float foamDistance = lerp(_FoamMaxDistance, _FoamMinDistance, normalDot);
				float foamDepthDifference01 = saturate(depthDifference / foamDistance);

				float surfaceNoiseCutoff = foamDepthDifference01 * _SurfaceNoiseCutoff;

				float2 distortSample = (tex2D(_SurfaceDistortion, i.distortUV).xy * 2 - 1) * _SurfaceDistortionAmount;

				// Distort the noise UV based off the RG channels (using xy here) of the distortion texture.
				// Also offset it by time, scaled by the scroll speed.
				float2 noiseUV = float2((i.noiseUV.x + _Time.y * _SurfaceNoiseScroll.x) + distortSample.x, 
				(i.noiseUV.y + _Time.y * _SurfaceNoiseScroll.y) + distortSample.y);
				float surfaceNoiseSample = tex2D(_SurfaceNoise, noiseUV).r;

				// Use smoothstep to ensure we get some anti-aliasing in the transition from foam to surface.
				// Uncomment the line below to see how it looks without AA.
				// float surfaceNoise = surfaceNoiseSample > surfaceNoiseCutoff ? 1 : 0;
				float surfaceNoise = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);

				float4 surfaceNoiseColor = _FoamColor;
				surfaceNoiseColor.a *= surfaceNoise;

				// Use normal alpha blending to combine the foam with the surface.
				float4 testingval = (1.0,1.0,1.0,1.0) * _WaterTransparency;
				return alphaBlend(surfaceNoiseColor, waterColor * testingval);
            }
            ENDCG
        }

    } // Subshader 1 end

	SubShader {
		Tags { "RenderType" = "Opaque" }
		CGPROGRAM
		#pragma surface surf Lambert

		struct Input {
			float2 uv_MainTex;
			float3 worldRefl;
		};

		sampler2D _MainTex;
		samplerCUBE _Cube;

		void surf (Input IN, inout SurfaceOutput o) {
			o.Albedo = tex2D (_MainTex, IN.uv_MainTex).rgb * 0.5;
			o.Emission = texCUBE (_Cube, IN.worldRefl).rgb;
		}
		ENDCG
    }
    Fallback "Diffuse"
}
