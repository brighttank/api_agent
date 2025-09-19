import 'package:analyzer/dart/element/element.dart';

import '../imports_builder.dart';
import '../utils.dart';
import 'endpoint_generator.dart';
import 'method_endpoint_generator.dart';
import 'use_types_generator.dart';

class ApiEndpointGenerator extends EndpointGenerator {
  final ClassElement element;
  final PropertyAccessorElement? accessor;

  ApiEndpointGenerator(this.element, this.accessor);

  @override
  late String endpointClassName = '${element.name}Endpoint';

  @override
  late String propertyName = accessor!.name ?? '';

  @override
  late String abstractMemberDefinition =
      '$endpointClassName get $propertyName;';

  @override
  late String constructedEndpoint = propertyName;

  @override
  void generate(
      StringBuffer output, Set<String> endpoints, ImportsBuilder imports) {
    if (endpoints.contains(element.name)) return;
    endpoints.add(element.name ?? '');

    var annotation = annotationChecker.firstAnnotationOf(element);

    var className = '${element.name}Endpoint';

    output.writeln(
        'mixin _${className}Mixin implements ApiEndpoint<$className> {\n'
        '  List<ApiEndpoint<dynamic>> get endpoints;\n'
        '\n'
        '  @override\n'
        '  void build(ApiBuilder builder) {');

    var typesGenerator = UseTypesGenerator();
    typesGenerator.addFromAnnotation(annotation);

    if (typesGenerator.typesOutput.isNotEmpty) {
      output.write(typesGenerator.generate());
    }

    output.writeln('    builder.mount(\'${element.name}\', endpoints');

    if (annotation != null && !annotation.getField('codec')!.isNull) {
      var codec = getMetaProperty(element, 'codec', imports);
      output.write('.withCodec($codec())');
      var uri =
          annotation.getField('codec')!.type?.element?.library?.uri;
      if (uri != null) imports.add(uri);
    }

    output.writeln(');\n'
        '  }\n'
        '}\n'
        'abstract class $className with _${className}Mixin {\n'
        '  static ApiEndpoint<$className> from({');

    var children = <EndpointGenerator>[];

    for (var method in element.methods) {
      if (method.isAbstract) {
        children.add(MethodEndpointGenerator(method, endpoints));
      }
    }

    for (var accessor in element.getters) {
      if (accessor.isAbstract) {
        var elem = accessor.type.returnType.element;
        if (elem == null || elem is! ClassElement) continue;
        children.add(ApiEndpointGenerator(elem, accessor));
      }
    }

    for (var child in children) {
      output.writeln(
          '    required ApiEndpoint<${child.endpointClassName}> ${child.propertyName},');
    }

    output.writeln(
        '  }) => _$className(${children.map((c) => c.propertyName).join(', ')});');

    for (var child in children) {
      output.writeln('\n  ${child.abstractMemberDefinition}');
    }

    output.writeln('  @override\n'
        '  List<ApiEndpoint<dynamic>> get endpoints => [');

    for (var child in children) {
      output.writeln('      ${child.constructedEndpoint},');
    }

    output.write('    ];\n'
        '}\n'
        'class _$className with _${className}Mixin {\n'
        '  _$className(${children.map((c) => 'this.${c.propertyName}Endpoint').join(', ')});\n'
        '');

    for (var child in children) {
      output.writeln('  final ApiEndpoint<${child.endpointClassName}> '
          '${child.propertyName}Endpoint;');
    }

    output.writeln('  @override\n'
        '  List<ApiEndpoint<dynamic>> get endpoints => \n'
        '    [${children.map((c) => '${c.propertyName}Endpoint').join(', ')}];\n'
        '}');

    for (var child in children) {
      child.generate(output, endpoints, imports);
    }
  }
}
