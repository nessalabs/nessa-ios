#!/usr/bin/env python3
"""Freeze the reviewed gateway wire grammar; normal app builds need no checkout."""
import argparse
import hashlib
import json
import pathlib
import subprocess

PIN = 'e45cdf9e18b487f7bbca5a401154d6a5649a6846'
ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ['protocol/product/v1.json', 'protocol/product/pairing-values.generated.json',
           'protocol/schemas/v1/frames.json', 'protocol/schemas/v1/common.json']
ENUMS = {'PairingOwnerPhase': 'GatewayPairingPhase', 'PairingTerminalCause': 'GatewayPairingTerminalCause',
         'PairingInitiatorKind': 'GatewayPairingInitiatorKind', 'PairingActivationStop': 'GatewayPairingActivationStop',
         'PairingErrorCode': 'GatewayPairingKnownError', 'PairingEnrollee': 'GatewayPairingEnrollee'}
META = {'description', 'x-rust-type', 'x-pairing-byte-array', 'x-pairing-manual-code', 'tsType', 'x-maxGrants'}

def literal(value):
    return json.dumps(value, ensure_ascii=False)

def rule(schema):
    keys = set(schema) - META
    if '$ref' in schema:
        assert keys == {'$ref'}, schema
        ref = schema['$ref']
        assert ref.startswith('#/$defs/') or ref == 'common.json#/$defs/GatewayError', ref
        return '.reference(' + literal(ref.split('/')[-1]) + ')'
    if not keys:
        return '.any'
    kind = schema.get('type')
    if keys == {'const'} and isinstance(schema['const'], str):
        return rule(dict(schema, type='string'))
    if isinstance(kind, list):
        assert kind in (['integer', 'null'], ['string', 'null']), schema
        return '.nullable(' + rule(dict(schema, type=kind[0])) + ')'
    if kind == 'object':
        assert keys <= {'type', 'additionalProperties', 'properties', 'required'}, schema
        assert schema['additionalProperties'] is False
        props = schema['properties']
        assert set(schema.get('required', [])) <= props.keys()
        fields = ', '.join(literal(k) + ': ' + rule(v) for k,v in sorted(props.items()))
        required = ', '.join(literal(k) for k in sorted(schema.get('required', [])))
        return '.object([' + fields + '], required: [' + required + '])'
    if kind == 'string':
        assert keys <= {'type', 'minLength', 'maxLength', 'enum', 'const', 'x-utf8MaxBytes', 'pattern'}, schema
        allowed = schema.get('enum', [schema['const']] if 'const' in schema else None)
        values = '[' + ', '.join(map(literal, allowed)) + ']' if allowed is not None else 'nil'
        if 'pattern' in schema or 'x-utf8MaxBytes' in schema:
            pattern = literal(schema['pattern']) if 'pattern' in schema else 'nil'
            return f'.constrainedText(minimum: {schema.get("minLength", 0)}, maximum: {schema.get("maxLength", "nil")}, bytes: {schema.get("x-utf8MaxBytes", "nil")}, allowed: {values}, pattern: {pattern})'
        return f'.string(minimum: {schema.get("minLength", 0)}, maximum: {schema.get("maxLength", "nil")}, allowed: {values})'
    if kind == 'integer':
        assert keys <= {'type', 'minimum', 'maximum', 'const'}, schema
        minimum = schema.get('const', schema.get('minimum', 0))
        maximum = schema.get('const', schema.get('maximum', 'nil'))
        assert minimum >= 0
        return f'.integer(minimum: {minimum}, maximum: {maximum})'
    if kind == 'boolean':
        assert keys == {'type'}, schema
        return '.boolean'
    if kind == 'array':
        # Uniqueness is the gateway's to keep; the phone checks shape and bounds.
        assert keys <= {'type', 'minItems', 'maxItems', 'items', 'uniqueItems'}, schema
        return f'.array(minimum: {schema.get("minItems", 0)}, maximum: {schema.get("maxItems", "nil")}, item: {rule(schema["items"])})'
    raise ValueError(f'Unsupported schema: {schema}')

def generate(checkout):
    revision = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    assert revision == PIN, 'Expected reviewed source revision ' + PIN
    assert not subprocess.check_output(['git', '-C', str(checkout), 'status', '--porcelain'], text=True).strip(), 'Source checkout must be clean'
    data = {p: (checkout / p).read_bytes() for p in SOURCES}
    schemas = {p: json.loads(v) for p,v in data.items()}
    defs = schemas[SOURCES[0]]['$defs']
    selected = {k:v for k,v in defs.items() if k.startswith('Pairing') or k in ('ProductSessionReady','ProductGrant','ProductResource')}
    roots = ['ConversationDeleteParams', 'ConversationReadParams', 'ConversationShareParams', 'ConversationSharesParams', 'ConversationSharesResult',
             'ConversationListParams', 'ConversationListResult', 'ConversationMutationResult',
             'ChannelListParams', 'ChannelListResult', 'PermissionReviewWaiting']
    def references(value):
        if isinstance(value, dict):
            if '$ref' in value:
                assert value['$ref'].startswith('#/$defs/'), value
                yield value['$ref'].split('/')[-1]
            for child in value.values():
                yield from references(child)
        elif isinstance(value, list):
            for child in value:
                yield from references(child)
    while roots:
        name = roots.pop()
        if name not in selected:
            selected[name] = defs[name]
            roots.extend(references(defs[name]))
    value_defs = schemas[SOURCES[1]]['$defs']
    for definition in selected.values():
        for prop in definition.get('properties', {}).values():
            if 'x-pairing-byte-array' in prop:
                owner = value_defs[prop['x-pairing-byte-array']]
                assert rule(prop) == rule(owner), 'Pairing owner byte bounds drift'
            if 'x-pairing-manual-code' in prop:
                assert rule(prop) == rule(value_defs['ManualCodeDisplay']), 'Manual code bounds drift'
    envelope = schemas[SOURCES[2]]['$defs']['ResFrame']
    expected = [{'properties': {'ok': {'const': True}}, 'required': ['payload'], 'not': {'required': ['error']}},
                {'properties': {'ok': {'const': False}}, 'required': ['error'], 'not': {'required': ['payload']}}]
    assert envelope['oneOf'] == expected, 'Response union changed; update the strict envelope decoder'
    envelope = dict(envelope)
    envelope.pop('oneOf')
    selected['ResFrame'] = envelope
    selected['GatewayError'] = schemas[SOURCES[3]]['$defs']['GatewayError']
    header = '// Generated by scripts/generate-gateway-pairing.py; do not edit.\n'
    header += '// Gateway revision: ' + revision + '\n'
    for p,b in data.items():
        header += '// SHA256 ' + p + ': ' + hashlib.sha256(b).hexdigest() + '\n'
    contracts = header + '\nimport Foundation\n\nenum GatewayWireContract {\n  static let rules: [String: GatewayWireRule] = [\n'
    for k,v in sorted(selected.items()):
        contracts += '    ' + literal(k) + ': ' + rule(v) + ',\n'
    contracts += '  ]\n}\n'
    enums = header + '\nimport Foundation\n'
    for key,name in ENUMS.items():
        enums += '\npublic enum ' + name + ': String, Codable, Sendable {\n'
        for val in defs[key]['enum']:
            parts = val.split('_')
            case = parts[0] + ''.join(s.title() for s in parts[1:])
            enums += '  case ' + case + ' = ' + literal(val) + '\n'
        enums += '}\n'
    return {'Sources/NessaFeatures/Infrastructure/GatewayWireContract.generated.swift': contracts,
            'Sources/NessaFeatures/Application/GatewayPairingEnums.generated.swift': enums}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout', type=pathlib.Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path,output in generate(args.checkout).items():
        target = ROOT / path
        if args.check:
            assert target.read_text() == output, 'Generated drift: ' + path
        else:
            target.write_text(output)
    print('Gateway pairing contract ' + ('matches' if args.check else 'generated'))

if __name__ == '__main__':
    main()
