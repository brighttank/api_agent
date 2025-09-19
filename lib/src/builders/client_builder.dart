import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';

import 'generators/use_types_generator.dart';
import 'imports_builder.dart';
import 'utils.dart';

class ClientApiBuilder {
  /// Main generation handler for client code
  Future<String> generateClients(
      List<LibraryElement> libraries, BuildStep buildStep) async {
    var imports = ImportsBuilder(buildStep.inputId)
      ..add(buildStep.inputId.uri)
      ..add(Uri.parse('package:api_agent/client.dart'));
    var exports = ImportsBuilder(buildStep.inputId, 'export')
      ..add(buildStep.inputId.uri);

    Map<String, String> clients = {};

    await for (var library in buildStep.resolver.libraries) {
      if (library.isInSdk) continue;

      for (var element in library.classes) {
        if (annotationChecker.hasAnnotationOf(element)) {
          generateClient(element, clients, imports);
        }
      }
    }

    return DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format('${imports.write()}\n'
            '${exports.write()}\n'
            '${clients.values.join('\n')}');
  }

  void generateClient(ClassElement element, Map<String, String> clients,
      ImportsBuilder imports) {
    if (clients.containsKey(element.name)) return;
    clients[element.name!] = '';

    var annotation = annotationChecker.firstAnnotationOf(element);

    var output = StringBuffer();

    output.write('class ${element.name}Client extends RelayApiClient {\n'
        '  ${element.name}Client(ApiClient client) '
        ': super(\'${element.name}\', client');

    if (annotation != null && !annotation.getField('codec')!.isNull) {
      var codec = getMetaProperty(element, 'codec');
      output.write(', $codec()');
      var uri = annotation.getField('codec')!.type?.element?.library?.uri;
      if (uri != null) imports.add(uri);
    }

    output.writeln(')');

    var methodOutput = StringBuffer();

    var typesGenerator = UseTypesGenerator();
    typesGenerator.addFromAnnotation(annotation);

    for (var method in element.methods) {
      if (method.isAbstract) {
        final positionalParams =
                method.formalParameters.where((param) => param.isPositional),
            optionalParams =
                method.formalParameters.where((param) => param.isNamed);

        String params = positionalParams.isEmpty
            ? ''
            : positionalParams.map((param) => param.toString()).join(', ');
        if (optionalParams.isNotEmpty) {
          params =
              '{${optionalParams.map((param) => param.toString().substring(1).replaceFirst('}', '')).join(',\n')}}';
        }

        methodOutput.write('\n'
            '  ${method.returnType} ${method.name!}($params) => \n'
            '    request(\'${method.name}\', {');

        for (var param in method.formalParameters) {
          if (method.formalParameters.first != param) {
            methodOutput.write(', ');
          }
          methodOutput.write("'${param.name}': ${param.name}");
        }

        methodOutput.write('}');

        if (method.typeParameters.isNotEmpty) {
          methodOutput.write(', ctx(['
              '${method.typeParameters.map((t) => t.name).join(', ')}])');
        } else {
          methodOutput.write(', null');
        }

        methodOutput.writeln(');');

        imports.addAll(method.getImports());
        typesGenerator.add([method.returnType]);
      }
    }

    if (typesGenerator.typesOutput.isNotEmpty) {
      output.writeln(' {\n  ${typesGenerator.generate()}}');
    } else {
      output.writeln(';');
    }

    output.write(methodOutput);

    for (var accessor in element.getters) {
      if (accessor.isAbstract) {
        var elem = accessor.type.returnType.element;
        if (elem == null || elem is! ClassElement) continue;
        output.writeln('\n'
            '  late final ${elem.name}Client ${accessor.name} = '
            '${elem.name}Client(this);');
        generateClient(elem, clients, imports);
      }
    }

    output.writeln('}');

    clients[element.name!] = output.toString();
  }
}
