export class WgslReflect {
  uniforms: unknown[] = [];
  textures: unknown[] = [];
  samplers: unknown[] = [];
  entry = {
    vertex: [{ inputs: [] as unknown[] }],
  };

  constructor(_source: string) {}
}
