export function normalizeArguments(input, schema, path = 'arguments', depth = 0) {
  if (depth >= 20) throw new Error('Tool arguments are too deeply nested.');
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (types.includes('null') && [null, '', 'null'].includes(input)) return null;
  if(schema.anyOf){for(const choice of schema.anyOf){try{return normalizeArguments(input,choice,path,depth+1);}catch{}}throw new Error(path+' does not match an accepted format.');}
  let value = input;
  const kind = types.find(type => type !== 'null');
  if (typeof value === 'string' && kind !== 'string') {
    const text = value.trim();
    if (kind === 'boolean' && ['true','false'].includes(text.toLowerCase())) value = text.toLowerCase() === 'true';
    else if (['integer','number'].includes(kind) && /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(text) && Number.isFinite(Number(text))) value = Number(text);
    else if (['array','object'].includes(kind)) { try { value = JSON.parse(value); } catch {} }
  }
  if (kind === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(path + ' needs named fields.');
    const properties = schema.properties ?? {}, result = Object.assign(Object.create(null), schema.additionalProperties === false ? {} : value);
    if (schema.additionalProperties === false && Object.keys(value).some(key => !Object.hasOwn(properties,key))) throw new Error(path + ' contains an unsupported field.');
    for (const [key, property] of Object.entries(properties)) {
      if (Object.hasOwn(value,key)) result[key] = normalizeArguments(value[key], property, key, depth + 1);
      else if ((schema.required ?? []).includes(key)) {
        if (Array.isArray(property.type) && property.type.includes('null')) result[key] = null;
        else throw new Error('The tool needs ' + key + '.');
      }
    }
    value = result;
  } else if (kind === 'array') {
    if (!Array.isArray(value) || value.length > (schema.maxItems ?? 10000) || value.length < (schema.minItems ?? 0)) throw new Error(path + ' needs a list within the supported size.');
    value = value.map(item => normalizeArguments(item, schema.items, path, depth + 1));
  } else if (['integer','number'].includes(kind)) {
    if (typeof value !== 'number' || !Number.isFinite(value) || (kind === 'integer' && !Number.isSafeInteger(value)) || value < (schema.minimum ?? -Infinity) || value > (schema.maximum ?? Infinity)) throw new Error(path + ' needs a number within the supported range.');
  } else if (kind === 'boolean') {
    if (typeof value !== 'boolean') throw new Error(path + ' needs true or false.');
  } else if (kind === 'string') {
    if (typeof value !== 'string' || [...value].length > (schema.maxLength ?? 4 * 1024 * 1024)) throw new Error(path + ' needs text within the supported size.');
  } else if(kind==='null'){if(value!==null)throw new Error(path+' must be null.');}
  else throw new Error('Unsupported parameter type.');
  if (schema.enum && !schema.enum.some(choice => JSON.stringify(choice) === JSON.stringify(value))) throw new Error(path + ' is not a supported choice.');
  return value;
}
