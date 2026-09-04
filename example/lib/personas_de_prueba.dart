/// Cien personas de prueba, con la forma exacta del modelo de identidad.
///
/// No es una lista de nombres: cada una trae lo que el SDK necesita para
/// demostrar las tres cosas que hay que poder probar sin un comercio real.
///
///   **el documento** — la cédula. Es lo que IDENTIFICA: único dentro del
///   comercio, y es lo que permite que un sistema de afuera pida un envío
///   —«mandale a la cédula 13185607»— sin conocer el `userId` interno.
///
///   🔴 Y es LO ÚNICO que identifica. El correo y el teléfono son direcciones, no
///   identificadores: una dirección la pueden compartir dos personas —dos hermanos
///   con el mismo teléfono es el caso más común de todos— así que no identifican a
///   nadie. Van entre los datos. Corregido el 2026-09-04, después de que este
///   archivo dijera lo contrario durante un rato.
///
///   **atributos** — nombre, sucursal, ciudad y plan. Son para FILTRAR y
///   MOSTRAR, no para direccionar. Es lo que permite probar el envío segmentado
///   —«a todos los de CCS-01», «a los del plan Bronce»— y la búsqueda en la
///   consola.
///
/// Los datos están repartidos a propósito: ocho ciudades, tres sucursales en
/// cada una y cuatro planes, de modo que cualquier filtro devuelva un grupo de
/// tamaño razonable y no uno ni cien. Un juego de prueba donde todos comparten
/// el mismo valor no prueba el filtro: prueba que la consulta corre.
///
/// **Todas entran con la misma clave: `admin123`**, y el usuario es `usuario1`
/// hasta `usuario100`. Es un juego de prueba: la clave es igual para las cien a
/// propósito, para poder entrar con cualquiera sin ir a buscarla.
///
/// 🔴 Y por eso mismo: esto NO se usa fuera de un ambiente de prueba. Cien
/// cuentas con la misma clave conocida es exactamente lo que no se hace en
/// ningún lado donde haya datos de alguien.
///
/// ══ 🔴 DE DÓNDE SALEN ESTOS DATOS, Y POR QUÉ NO PUEDEN SALIR DE ACÁ ══
///
/// **Reconciliadas el 2026-09-04 con la cartera de prueba de notificaciones**, por pedido de
/// Juan: *«vamos a hacer que la app de Flutter de Collection tenga las identidades de los
/// cien que tenemos actualmente, con toda esa data»*.
///
/// El motivo es concreto: hasta hoy los dos sistemas tenían cien personas inventadas **cada
/// uno por separado, sin una sola cédula en común**. Medido: Collection tenía la cédula
/// `12137717` y notificaciones la `13185607`. Con juegos que no se cruzan no se puede probar
/// una integración de punta a punta — un envío que sale de acá no le llega a nadie de allá.
///
/// Ahora el `userId` de cada persona **es el mismo identificador con el que existe en
/// notificaciones**, así que las dos puntas hablan de la misma gente.
///
/// 🔴 **Y por eso mismo: estos nombres, cédulas, teléfonos y correos NO son inventados.**
/// Vienen de la cartera de desarrollo, y parecen de personas reales. Esta lista no puede
/// salir de un ambiente de prueba: no se compila en un APK que se distribuya, y ningún envío
/// de prueba puede dispararse contra estos teléfonos —son números que existen y cuestan
/// plata—. Contra el simulador de proveedor, o no se prueba.
///
/// El texto que estaba acá decía que las cédulas y los correos eran inventados. Dejarlo
/// habría sido una mentira en el código, del tipo que hace que alguien despliegue esto sin
/// pensarlo dos veces.
///
/// ## Los cuatro casos del modelo de identidad
///
/// Las cien de abajo son todas personas naturales con cédula — el caso de
/// siempre. Al final de este archivo hay CUATRO más, agregadas con el
/// rediseño de colecciones, que prueban lo que las cien no pueden: DOS
/// **empresas** (`TipoDeSujeto.juridica`, documento con `ClaseDeDocumento.rif`)
/// y DOS **empleados de un proveedor** (naturales, pero con [Organizacion] —
/// el sujeto PERTENECE a la organización, no se reemplaza por ella). Ver
/// [casosDeIdentidadDePrueba].
library;

import 'package:hz_collection_sdk/hz_collection_sdk.dart';

/// Una persona del juego de prueba.
class PersonaDePrueba {
  const PersonaDePrueba({
    required this.userId,
    required this.cedula,
    required this.correo,
    required this.nombre,
    this.telefono = '',
    this.pais = '',
    this.estado = '',
    this.ciudad = '',
    this.genero = '',
    /// 🔴 `usuario`, `sucursal` y `plan` NO ESTÁN EN EL EXCEL — corregido por Juan el
    /// 2026-09-04: *«esos no son datos míos, yo tengo un UUID o un identificador; apegate a
    /// lo que tengo en el Excel»*.
    ///
    /// Quedan declarados con valor vacío por omisión, y sólo por los cuatro casos de
    /// identidad del final que los venían usando. **Las cien no los llevan**: inventar tres
    /// columnas que el archivo no tiene es exactamente cómo una prueba deja de probar el
    /// caso real — se filtra por una sucursal que en la cartera de verdad no existe, y el
    /// filtro pasa.
    this.usuario = '',
    this.sucursal = '',
    this.plan = '',
    this.tipo = TipoDeSujeto.natural,
    this.claseDeDocumento = ClaseDeDocumento.cedula,
    this.organizacion,
  });

  /// La clave con la que el comercio la identifica. Opaca para el SDK.
  ///
  /// En estas personas de prueba se compone a propósito —`usuario1-12137717`— en vez de ser
  /// un `u_9000` cualquiera: en la consola del proveedor se ve el identificador, y uno opaco
  /// obliga a ir a buscar de quién es cada vez. En un comercio de verdad será lo que él use.
  final String userId;

  /// Con qué entraba en el juego viejo. **Vacío en las cien**: no está en el Excel.
  final String usuario;

  // ── alias · se direcciona por acá ──────────────────────────────────────
  //
  // 🔴 El nombre del campo quedó de cuando sólo existían personas naturales.
  // Para los cuatro casos de [casosDeIdentidadDePrueba] guarda el número de
  // documento que corresponda —un RIF para las empresas—, y [claseDeDocumento]
  // dice cuál es. No se renombró el campo para no tocar las cien de abajo.
  final String cedula;
  final String correo;

  // ── atributos · se filtra y se muestra por acá ─────────────────────────
  //
  // 🔴 De acá salieron `sucursal` y `plan`, que NO están en el Excel. Los cortes de verdad
  // son `estado` —20 valores, de 1 a 18 personas— y `ciudad`, que son datos del comercio.
  //
  // 🔴 EL TELÉFONO VA ACÁ, Y NO ENTRE LOS IDENTIFICADORES — corregido por Juan el
  // 2026-09-04: *«el teléfono es el teléfono, el alias es la cédula»*.
  //
  // Yo lo había puesto entre los alias razonando que «por ahí se direcciona», y ese
  // razonamiento es de OTRO sistema. Acá no aplica por dos motivos, y los dos importan:
  //
  //   · **Collection manda push, no SMS.** Un push va al token del aparato, nunca a un
  //     número. Collection no direcciona por teléfono nunca: quien lo hace es
  //     notificaciones, y allá el teléfono ya tiene su rol declarado (`CONTACT`).
  //
  //   · **Un identificador identifica a UNA persona.** Dos hermanos comparten un teléfono
  //     —es el caso más común de todos— así que un teléfono no identifica a nadie. Tratarlo
  //     como identificador es exactamente el defecto que el resolvedor de notificaciones
  //     ataja registrando un conflicto en vez de fusionar dos personas.
  //
  // La identidad es el documento. El teléfono es un dato de la persona, igual que el correo
  // —que de hecho ya viajaba en `datos` en `main.dart`, y era `comoAlta` el que estaba
  // inventando un cajón que el servicio no tiene—.
  final String telefono;
  final String nombre;
  final String sucursal;
  final String ciudad;
  final String plan;

  /// Los tres que trajo la reconciliación. Son para filtrar: `estado` es el corte que de
  /// verdad reparte la cartera —veinte grupos, de 1 a 18 personas— mientras `ciudad` tiene
  /// cincuenta y dos valores y deja grupos de dos, que no prueban ningún filtro.
  final String pais;
  final String estado;
  final String genero;

  /// Si es una persona natural o una empresa. Por omisión, natural: es lo que
  /// son las cien de abajo.
  final TipoDeSujeto tipo;

  /// Con qué clase de documento se identifica [cedula]. Por omisión, cédula.
  final ClaseDeDocumento claseDeDocumento;

  /// La organización a la que pertenece, si tiene una. `null` en las cien:
  /// no todo el mundo trabaja para un proveedor del comercio.
  final Organizacion? organizacion;

  /// El documento tal como lo espera `AkPush.alIniciarSesion`. Se arma desde
  /// [cedula] y [claseDeDocumento]: son las dos empresas las que cambian la
  /// clase, no el campo — así el resto del demo no se entera de la diferencia.
  Documento get documento => Documento(clase: claseDeDocumento, numero: cedula);

  /// Lo que el backend del comercio le mandaría al servicio para darla de alta.
  /// Lo que el backend del comercio le mandaría al servicio para darla de alta.
  ///
  /// 🔴 SÓLO LAS COLUMNAS DEL EXCEL. La identidad es el documento; el resto son datos.
  Map<String, dynamic> get comoAlta => {
        'userId': userId,
        'alias': {'cedula': cedula},
        'atributos': {
          'nombre': nombre,
          'correo': correo,
          if (telefono.isNotEmpty) 'telefono': telefono,
          if (pais.isNotEmpty) 'pais': pais,
          if (estado.isNotEmpty) 'estado': estado,
          if (ciudad.isNotEmpty) 'ciudad': ciudad,
          if (genero.isNotEmpty) 'genero': genero,
        },
      };

  @override
  String toString() => '$usuario · $nombre · $cedula · $sucursal · $plan';
}

/// Las cien.
/// La contraseña de las cien. Igual para todas, a propósito y sólo para probar.
const claveDePrueba = 'admin123';

const cienPersonas = <PersonaDePrueba>[
  PersonaDePrueba(
    userId: '6693ea988b7b3a506c2aa58e',
    cedula: '13185607',
    nombre: 'Ivan Murzi Lopez',
    telefono: '+584247111443',
    correo: 'murzilopezi@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Santa Teresa del Tuy',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '69bdbc5b5aa734219afed294',
    cedula: '26051970',
    nombre: 'Linnet Montoya',
    telefono: '+584144944612',
    correo: 'linnetmontoya1208@gmail.com',
    pais: 'Venezuela',
    estado: 'Aragua',
    ciudad: 'Maracay',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '676dc59e8cc125da8f90e289',
    cedula: '17229393',
    nombre: 'Jesús Alexander Loyo Solís',
    telefono: '+584123716221',
    correo: 'jesusloyo348@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Barquisimeto',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '66f98738c5430b462e4999ba',
    cedula: '18906519',
    nombre: 'Marielba Balza Zambrano',
    telefono: '+584143544954',
    correo: 'maricar5588@gmail.com',
    pais: 'Venezuela',
    estado: 'Barinas',
    ciudad: 'Barinas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6a15bcfb937287c54ffa5835',
    cedula: '20946420',
    nombre: 'Erwin Daniel Pineda Morillo',
    telefono: '+584246691808',
    correo: 'edapim12@gmail.com',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'Maracaibo',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '67622ae828df99169d59004c',
    cedula: '30379380',
    nombre: 'Joelimar Brito',
    telefono: '+584247253332',
    correo: 'luisahenriquez647@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Cumaná',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '685d9e58ceb7859159821503',
    cedula: '28020186',
    nombre: 'Jhonnar Alberto González Peña',
    telefono: '+584264552908',
    correo: 'gonzalezjhonnar@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Barquisimeto',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '663e58be853c3b3dda5b2cab',
    cedula: '25358741',
    nombre: 'Ramon Celestino Barreto',
    telefono: '+584128411375',
    correo: 'barretocramon@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'San José de Guanipa (El Tigrito)',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '66bb8d8e9ae2ac1f4203fbae',
    cedula: '5666835',
    nombre: 'Nancy Zambrano Pantaleon',
    telefono: '+584165020532',
    correo: 'nancyczambrano@yahoo.es',
    pais: 'Venezuela',
    estado: 'Táchira',
    ciudad: 'San Cristobal',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6792aeae4d4c4d051dcfca72',
    cedula: '13937553',
    nombre: 'Iris Flores',
    telefono: '+584125450015',
    correo: 'irisjhoseptaa@gmail.com',
    pais: 'Venezuela',
    estado: 'Barinas',
    ciudad: 'Barinas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69445173ca72813b8353cde1',
    cedula: '28155206',
    nombre: 'Joemil Carrixales',
    telefono: '+584241214852',
    correo: 'joemilcarrizales2@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Baruta',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '65ac4f589efc433b8da8cc56',
    cedula: '26471003',
    nombre: 'Luis Bracho Acosta',
    telefono: '+584126831787',
    correo: 'bracho488@gmail.com',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'San Francisco',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '68c788fcad3fbbc0727010cd',
    cedula: '13696845',
    nombre: 'Katerin Katiuska Barrios',
    telefono: '+584121553358',
    correo: 'katerinbarrios49@gmail.com',
    pais: 'Venezuela',
    estado: 'Yaracuy',
    ciudad: 'Guama',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '680b64f7285c51d9d2f582d6',
    cedula: '20343971',
    nombre: 'Elizabeth Guaita Jiménez',
    telefono: '+584264809921',
    correo: 'elizabethguaita3@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'Barcelona',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6928c5243fce7ec90e67b59f',
    cedula: '16257974',
    nombre: 'Carlos Marcano',
    telefono: '+584248096242',
    correo: 'camd.2106@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6a121f731231d3d7b1ccab7a',
    cedula: '33374137',
    nombre: 'Angelica Sandrea',
    telefono: '+584246933611',
    correo: 'angelicasandrea20@gmail.com',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'Cabimas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '659d5a4e19fe66249ffdc827',
    cedula: '19316726',
    nombre: 'Jose Mejias Nolasco',
    telefono: '+584120422179',
    correo: 'jsmejia70@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '696ae20fcd6f6e2834177f07',
    cedula: '32756463',
    nombre: 'Paola Figuera',
    telefono: '+584160293123',
    correo: 'paolafiguera840@gmail.com',
    pais: 'Venezuela',
    estado: 'La Guaira',
    ciudad: 'Catia La Mar',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '672d2c38aa6a03e2727a85cd',
    cedula: '24206416',
    nombre: 'Anaidys Mujica',
    telefono: '+584126668935',
    correo: 'anaidysmujica120@gmail.com',
    pais: 'Venezuela',
    estado: 'Falcón',
    ciudad: 'Punto Fijo',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6949bc42ca72813b83ab4367',
    cedula: '18484854',
    nombre: 'Mayelis Del Carmen Gauna Cardozo',
    telefono: '+584262196335',
    correo: 'mayelisgauna03@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67eb0f7bbee4d26ad9816b57',
    cedula: '31456967',
    nombre: 'Mariana Machado',
    telefono: '+584244139646',
    correo: 'machadoroblesmariana@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6a297bf1ddca792936ec3eb8',
    cedula: '24680346',
    nombre: 'Aiker Antonio Viscaya Guedez',
    telefono: '+584245765376',
    correo: 'aikerantonioviscayaguedez@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Barquisimeto',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '68ec266a8483d77de766c16a',
    cedula: '27529936',
    nombre: 'Anabela Marcantonio',
    telefono: '+584121531319',
    correo: 'anabelamarcantonio@gmail.com',
    pais: 'Venezuela',
    estado: 'Yaracuy',
    ciudad: 'Independencia',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6712665ef4fd75e6af0a296b',
    cedula: '18834902',
    nombre: 'Edgar Farfan',
    telefono: '+584127450200',
    correo: 'farfan.edgareduardo@gmail.com',
    pais: 'Venezuela',
    estado: 'Guárico',
    ciudad: 'Valle de La Pascua',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '68cdc84ac2cca96f1db0107c',
    cedula: '5700849',
    nombre: 'Maria Diaz',
    telefono: '+584167155248',
    correo: 'malengo1958@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67fb0503e2974ab77ee51d5a',
    cedula: '20082649',
    nombre: 'Iralic Rodriguez',
    telefono: '+584244198681',
    correo: 'solianytorres12@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Guigue',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '688bc6d7158050eb713b88d7',
    cedula: '15379713',
    nombre: 'Luz Rondon',
    telefono: '+584142358278',
    correo: 'lyrondon.2014@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '665a41e782af16211f0bcc64',
    cedula: '12783874',
    nombre: 'Jessika Yuslemis Hernandez Dugarte',
    telefono: '+584241642887',
    correo: 'jessikah0220@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '681103593106f27739ff30e4',
    cedula: '26522095',
    nombre: 'Endimar Rodríguez',
    telefono: '+584124920840',
    correo: 'endimarodriguez@gmail.com',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'Ciudad Ojeda',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69a3309a706de03c9473deab',
    cedula: '15111557',
    nombre: 'Pedro Lanza',
    telefono: '+584127009429',
    correo: 'pedrolanza00@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Cumaná',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6577568df87e9d1c9b454a5e',
    cedula: '14130610',
    nombre: 'Angy Barrios Mendez',
    telefono: '+584242875889',
    correo: 'karh.cake@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6854d6760a9f1ab9644af83f',
    cedula: '15509528',
    nombre: 'Yoana Rondón',
    telefono: '+584123798716',
    correo: 'yoanarondon120@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'San Tomé',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6839cb64ef3c3c33f6f9e6b4',
    cedula: '17217406',
    nombre: 'Ignacio Sánchez',
    telefono: '+584127584089',
    correo: 'sanchez.02nacho@gmail.com',
    pais: 'Venezuela',
    estado: 'Bolívar',
    ciudad: 'Ciudad Guayana',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6a4bdba5cb2773722d9e8e28',
    cedula: '13152829',
    nombre: 'Luis Vegas',
    telefono: '+584242659780',
    correo: 'luisr.vegasv@gmail.com',
    pais: 'Venezuela',
    estado: 'Guárico',
    ciudad: 'San Juan de Los Morros',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6797ff4cc7a3470d6ba47163',
    cedula: '17000843',
    nombre: 'Maribel Del Valle Vasquez Gutierrez',
    telefono: '+584142958206',
    correo: 'maribel.vg7@yahoo.com',
    pais: 'Venezuela',
    estado: 'Guárico',
    ciudad: 'Valle de La Pascua',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '675ce9113c745658586583f7',
    cedula: '28628972',
    nombre: 'Franyolis Campos',
    telefono: '+584248321946',
    correo: 'franyoliscampos5@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'Barcelona',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67d60cc742e7ba716da000cb',
    cedula: '20716496',
    nombre: 'Carlos David García',
    telefono: '+584140638517',
    correo: 'garciscarlos@gmail.com',
    pais: 'Venezuela',
    estado: 'Táchira',
    ciudad: 'La Grita',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '67ca44a97c760bdc3a1316ad',
    cedula: '11390011',
    nombre: 'Luis Antonio Saavedra Virla',
    telefono: '+584125643996',
    correo: 'saavedraluis63@gmail.com',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'San Francisco',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6789969f4d4c4d051db2b86e',
    cedula: '30223978',
    nombre: 'Siandry Silano',
    telefono: '+584128405227',
    correo: 'sina.silano21@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'Barcelona',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '680bf4c1ad0d735311e0cd65',
    cedula: '16031844',
    nombre: 'Gordan Hernández',
    telefono: '+584242716874',
    correo: 'jordanlo3915@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '647a2b2289532a071f7727f7',
    cedula: '26466407',
    nombre: 'Oriana Garcia Larrua',
    telefono: '+584241484353',
    correo: 'orianagarcial2801@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69431554d1ba073bd746201d',
    cedula: '27760662',
    nombre: 'Julian Martinez',
    telefono: '+584165378775',
    correo: 'julianmartinez.uenza@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Barquisimeto',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '66203339995421486318e002',
    cedula: '27287499',
    nombre: 'Daniela Vittorioso Salazar',
    telefono: '+584242751755',
    correo: 'vittoriosodaniela@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Los Teques',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '68fa9f6989346971bf71639f',
    cedula: '10691263',
    nombre: 'Marilu Guarini Rodriguez',
    telefono: '+584142618474',
    correo: 'mariluguarini@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Guarenas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67e813886ec1c43338f8c702',
    cedula: '17473766',
    nombre: 'Yordin Zambrano',
    telefono: '+584241956113',
    correo: 'yordinzambrano17@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'San Francisco de Yare',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '693505eeb5314d04cee34e14',
    cedula: '32077422',
    nombre: 'Fabiana Peraza',
    telefono: '+584145684035',
    correo: 'perazafabiana14@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Barquisimeto',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6697e33c6ed9b64dbd7857d7',
    cedula: '13750276',
    nombre: 'Yris Del Valle Duran De Uribe',
    telefono: '+584142155883',
    correo: 'duranyris15@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '68dc560041477e8046903ac2',
    cedula: '23899737',
    nombre: 'Yoseline Salazar',
    telefono: '+584249331463',
    correo: 'yosesalazar39@gmail.com',
    pais: 'Venezuela',
    estado: 'Monagas',
    ciudad: 'Maturín',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67fc541eed3cba680c12e408',
    cedula: '10380221',
    nombre: 'Nelson Torres',
    telefono: '+584141221314',
    correo: 'nelsont284@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '67df0db1f16348cef233ad56',
    cedula: '31604511',
    nombre: 'Carlos Martinez',
    telefono: '+584124325094',
    correo: 'cm347921@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'El Tigre',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '68261b8531a6ea08549fbaee',
    cedula: '18607458',
    nombre: 'Eunimer Castillo',
    telefono: '+584246909168',
    correo: 'consuelocastillo753@gmail.com',
    pais: 'Venezuela',
    estado: 'Falcón',
    ciudad: 'Coro',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67feed86afd168e5627b91e0',
    cedula: '19064199',
    nombre: 'Natasha Seijas',
    telefono: '+584241356509',
    correo: 'natashaseijasa@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6a4f1416063573f5ea76a809',
    cedula: '17596892',
    nombre: 'Juan Becerra',
    telefono: '+584120165853',
    correo: 'juancarlosbecerra477@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '675e23a78358510506d9e042',
    cedula: '13654994',
    nombre: 'Fernando Garcia',
    telefono: '+584168918026',
    correo: 'gmfsantil2020@gmail.com',
    pais: 'Venezuela',
    estado: 'Monagas',
    ciudad: 'Maturín',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6740d6fecfe44d4341921bd3',
    cedula: '11100093',
    nombre: 'Dilcia Mercedes Moreno Gonzales',
    telefono: '+584127011255',
    correo: 'dilciamercedesmoreno@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'El Palito',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '68e906e1a46baed36b8a70eb',
    cedula: '18214423',
    nombre: 'Mercedes Gómez',
    telefono: '+584165334167',
    correo: 'gd884488@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Tunapuy',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67f6b5bbf4312d7d122cd5c4',
    cedula: '23505498',
    nombre: 'Yaniris Rondon',
    telefono: '+584148651314',
    correo: 'yanirislaprincerondon@hotmail.com',
    pais: 'Venezuela',
    estado: 'Bolívar',
    ciudad: 'Ciudad Guayana',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6980d9350bf8d4e62b83b9eb',
    cedula: '13637588',
    nombre: 'Ysbelis Antuarez',
    telefono: '+584125126135',
    correo: 'bernardinosan584@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '68d8b9ccda379f27664eb3ee',
    cedula: '26008346',
    nombre: 'Zorismar Zambrano Ortega',
    telefono: '+584124446697',
    correo: 'zambranozorianny@gmail.com',
    pais: 'Venezuela',
    estado: 'Guárico',
    ciudad: 'Valle de La Pascua',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6a3ac678f89b876dd94fe271',
    cedula: '26049396',
    nombre: 'Ivanny Yanez',
    telefono: '+584125082721',
    correo: 'ivannyyanez@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Barquisimeto',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69a428f5c4bf6edbfaefbdef',
    cedula: '27798524',
    nombre: 'Luis Sánchez',
    telefono: '+584123071137',
    correo: 'lss4nch3z3@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'El Junquito',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '66004850dcd2bc2cce29733a',
    cedula: '26181365',
    nombre: 'Erick Gonzalez Molleja',
    telefono: '+584121429211',
    correo: 'erick-120_@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Cabudare',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '675c950a02dc7d36ba0d0207',
    cedula: '15877472',
    nombre: 'Dennis Reyes',
    telefono: '+584121117437',
    correo: 'dennisreyesparroco@gmail.com',
    pais: 'Venezuela',
    estado: 'Monagas',
    ciudad: 'Aragua de Maturín',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '690693c389346971bfe9ff8f',
    cedula: '23390900',
    nombre: 'Dayre Yorlet Rodriquez Angulo',
    telefono: '+584247350891',
    correo: 'dayrerodriguez743@gmail.com',
    pais: 'Venezuela',
    estado: 'Mérida',
    ciudad: 'Ejido',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69ebfdd62631ba1bc0fc0e42',
    cedula: '27987247',
    nombre: 'Paola Rodriguez',
    telefono: '+584245642340',
    correo: 'rpaola1827@gmail.com',
    pais: 'Venezuela',
    estado: 'Lara',
    ciudad: 'Tintorero',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67179928e8ec37a7fc4e7ec4',
    cedula: '6882580',
    nombre: 'Omaira Sanchez',
    telefono: '+584127720561',
    correo: 'freymg@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Campo de Carabobo',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6768389e4d2846814fd36c0a',
    cedula: '17005038',
    nombre: 'Yennifer Bellio',
    telefono: '+584127337398',
    correo: 'yennifermariabelliosanchez@gmail.com',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'Los Puertos de Altagracia',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '64f38328e0cd400e855989c9',
    cedula: '14163407',
    nombre: 'Yaksi Castillo Lopenza',
    telefono: '+584241758469',
    correo: 'yaksimontebugnoli@gmail.com',
    pais: 'Venezuela',
    estado: 'La Guaira',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6a04f1b80ad994d79144bee0',
    cedula: '13959432',
    nombre: 'Freddy Perez',
    telefono: '+584122515145',
    correo: 'fredenry2015@gmail.com',
    pais: 'Venezuela',
    estado: 'Portuguesa',
    ciudad: 'Guanare',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '693d68d2ca72813b83d2ccbf',
    cedula: '20141856',
    nombre: 'Fidel Bustamante',
    telefono: '+584247400399',
    correo: 'fidelabustamantej@gmail.com',
    pais: 'Venezuela',
    estado: 'Mérida',
    ciudad: 'El Vigía',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '66cc25aaad61834f68ade4d5',
    cedula: '12955856',
    nombre: 'Yurelki Margarita Chirinos Meléndez',
    telefono: '+584242874455',
    correo: 'yurelkichirinos@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '691ce85675c7e43b8dcbe021',
    cedula: '14654707',
    nombre: 'Willian Paez',
    telefono: '+584246702745',
    correo: 'albertopaezwillian0031@gmail.com',
    pais: 'Venezuela',
    estado: 'Falcón',
    ciudad: 'Coro',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '679c22aa064cc307eaace1c9',
    cedula: '22388130',
    nombre: 'Juan Carlos Cisneros',
    telefono: '+584129708654',
    correo: '12-10330@usb.ve',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Baruta',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6962b114ecf499fbbafc2286',
    cedula: '18152040',
    nombre: 'Yurmery Carolina Polanco Valles',
    telefono: '+584146150778',
    correo: 'polancoyurmeryyp@gmail.com',
    pais: 'Venezuela',
    estado: 'Falcón',
    ciudad: 'Coro',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67a2840d5e96342af1b6c3aa',
    cedula: '31383561',
    nombre: 'Greiker Vasquez',
    telefono: '+584121830708',
    correo: 'greikervasquez15@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Charallave',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6a2fe62d08274b6e49f44f39',
    cedula: '19199995',
    nombre: 'Mariela Diaz',
    telefono: '+584241290652',
    correo: 'mariediaz989@gmail.com',
    pais: 'Venezuela',
    estado: 'Mérida',
    ciudad: 'La Blanca (12 de Octubre)',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '64ecada921538a4a993da5d7',
    cedula: '16058591',
    nombre: 'Maria Lobeto Gonzalez',
    telefono: '+584162107735',
    correo: 'marfer1703@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69e405ec66eb3db1872a24fd',
    cedula: '25100122',
    nombre: 'Reinaldo Castañeda',
    telefono: '+584141895712',
    correo: 'reinaldojcc256@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Cumaná',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '6a398dbfddca7929367b704e',
    cedula: '24225759',
    nombre: 'Yurbelys Hernández',
    telefono: '+584125579498',
    correo: 'yurbelyshernandez23@gmail.com',
    pais: 'Venezuela',
    estado: 'Aragua',
    ciudad: 'Santa Rita',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67e569b88052fd21e891dd55',
    cedula: '20112974',
    nombre: 'Jesusita Del Valle Guerra Rivas',
    telefono: '+584147853481',
    correo: 'jesusitaguerra2020@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Cumaná',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6a0772ae0ad994d7915c9d48',
    cedula: '30994948',
    nombre: 'Fransheska Brito',
    telefono: '+584248867680',
    correo: 'fransheskabrito27@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'El Tigre',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6757b231a62ff256ea4465b3',
    cedula: '4431392',
    nombre: 'Ercilia Calderón',
    telefono: '+584247295187',
    correo: 'erciliaram.28@gmail.com',
    pais: 'Venezuela',
    estado: 'Trujillo',
    ciudad: 'Valera',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6758ad97a62ff256ea48f5a9',
    cedula: '20126449',
    nombre: 'Carlos Leonardo Gaglio Maiz',
    telefono: '+584248161028',
    correo: 'carlos_gaglio@hotmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Cariaco',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '65f5d67dde1b497b598f2307',
    cedula: '14047855',
    nombre: 'Vianney Veliz',
    telefono: '+584249009511',
    correo: 'vianneyveliz6@gmail.com',
    pais: 'Venezuela',
    estado: 'Monagas',
    ciudad: 'Maturín',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '65f0486bee4a396c3a6d76cf',
    cedula: '18557658',
    nombre: 'Leidy Jaimes Cuauro',
    telefono: '+584241086254',
    correo: 'carolina.leidy@yahoo.com.be',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67e59c738052fd21e8933f5f',
    cedula: '16456734',
    nombre: 'Quervis Jose Nelson Díaz',
    telefono: '+584246276621',
    correo: 'quervis.nelson@dsg.luz.edu.ve',
    pais: 'Venezuela',
    estado: 'Zulia',
    ciudad: 'Maracaibo',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67070001958c6619afbc2d22',
    cedula: '16023864',
    nombre: 'Michelle Bermúdez',
    telefono: '+584121303060',
    correo: 'michebermudes@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6763204d4d2846814fb29906',
    cedula: '20696925',
    nombre: 'Miguel Andres Gomez Palencia',
    telefono: '+584144284978',
    correo: 'miguelagp2601@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '68b0d4fe5ae228d462de6c79',
    cedula: '30239870',
    nombre: 'Darlin Ramos',
    telefono: '+584241709508',
    correo: 'darlinramoss2025@gmail.com',
    pais: 'Venezuela',
    estado: 'Distrito Capital',
    ciudad: 'Caracas',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '693c45e2ca72813b83c516fc',
    cedula: '23503890',
    nombre: 'Mariangi Angeli',
    telefono: '+584149885271',
    correo: 'mariangiangeli28@gmail.com',
    pais: 'Venezuela',
    estado: 'Bolívar',
    ciudad: 'Ciudad Guayana',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6869811da60c0fff144868f2',
    cedula: '29655486',
    nombre: 'Sofía Santamaría',
    telefono: '+584128769794',
    correo: 'sofiasantamaria010203@gmail.com',
    pais: 'Venezuela',
    estado: 'Anzoátegui',
    ciudad: 'Puerto La Cruz',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '69add42549ea025f0ddce6d4',
    cedula: '22651009',
    nombre: 'Jose Zabala',
    telefono: '+584122974494',
    correo: 'josezabala817@gmail.com',
    pais: 'Venezuela',
    estado: 'Nueva Esparta',
    ciudad: 'La Guardia',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '676eb0294d2846814ff254ff',
    cedula: '27481716',
    nombre: 'Gabriel Zambrano',
    telefono: '+584244443278',
    correo: 'gzambrano2306@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '66e205b1d3a22a4853d5a573',
    cedula: '18094733',
    nombre: 'Krisbell Castro',
    telefono: '+584126146513',
    correo: 'krisbellcastro2020@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '6860619cceb78591599439c3',
    cedula: '23945304',
    nombre: 'Juricar Luna',
    telefono: '+584129135206',
    correo: 'juricarluna@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Carúpano',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '67732b8a4d4c4d051d72dae8',
    cedula: '26592049',
    nombre: 'Magus Meudon',
    telefono: '+584241206945',
    correo: 'magusmeudon@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Cumaná',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '67644bdc4d4c4d051d22a5c2',
    cedula: '14251035',
    nombre: 'Joel Reyes',
    telefono: '+584129135257',
    correo: 'jimenezjr25@gmail.com',
    pais: 'Venezuela',
    estado: 'Carabobo',
    ciudad: 'Valencia',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '67a66ee90bb093d3aeea4cad',
    cedula: '12289642',
    nombre: 'Rosangel Delvalle Rodriguez Gonzalez',
    telefono: '+584120603594',
    correo: 'rodriguezrosangeldelvalle07@gmail.com',
    pais: 'Venezuela',
    estado: 'Sucre',
    ciudad: 'Carúpano',
    genero: 'Femenino',
  ),
  PersonaDePrueba(
    userId: '683206548c328a7240ea4b9e',
    cedula: '19829092',
    nombre: 'Fred David Palacios Flores',
    telefono: '+584142867307',
    correo: 'fredpalacios6@gmail.com',
    pais: 'Venezuela',
    estado: 'Miranda',
    ciudad: 'Ocumare del Tuy',
    genero: 'Masculino',
  ),
  PersonaDePrueba(
    userId: '67193ff4f4fd75e6af1bf0cd',
    cedula: '13681536',
    nombre: 'Nestor Herrera',
    telefono: '+584121428155',
    correo: 'nestorherrera044@gmail.com',
    pais: 'Venezuela',
    estado: 'Guárico',
    ciudad: 'El Socorro',
    genero: 'Masculino',
  ),
];

// ── Atajos para armar pruebas sin recorrer la lista a mano ────────────────

/// Las sucursales que existen en el juego de prueba, ordenadas.
List<String> get sucursalesDePrueba =>
    (cienPersonas.map((p) => p.sucursal).toSet().toList()..sort());

/// Los planes que existen.
List<String> get planesDePrueba =>
    (cienPersonas.map((p) => p.plan).toSet().toList()..sort());

/// Las de una sucursal. Para probar el envío segmentado.
List<PersonaDePrueba> deLaSucursal(String sucursal) =>
    cienPersonas.where((p) => p.sucursal == sucursal).toList();

/// Las de un plan.
List<PersonaDePrueba> delPlan(String plan) =>
    cienPersonas.where((p) => p.plan == plan).toList();

/// Buscar por cédula, que es el caso de uso que motivó todo el modelo de alias:
/// el emisor conoce la cédula y no el `userId`.
PersonaDePrueba? porCedula(String cedula) {
  for (final p in cienPersonas) {
    if (p.cedula == cedula) return p;
  }
  return null;
}

/// Entrar como la enésima. `porUsuario('usuario7')` o `laNumero(7)` — lo mismo.
PersonaDePrueba? porUsuario(String usuario) {
  for (final p in cienPersonas) {
    if (p.usuario == usuario) return p;
  }
  return null;
}

/// La enésima, de 1 a 100.
PersonaDePrueba? laNumero(int n) =>
    (n < 1 || n > cienPersonas.length) ? null : cienPersonas[n - 1];

/// Buscar por parecido en el nombre, que es lo que hace la consola.
List<PersonaDePrueba> buscarPorNombre(String texto) {
  final t = texto.trim().toLowerCase();
  if (t.isEmpty) return const [];
  return cienPersonas
      .where((p) => p.nombre.toLowerCase().contains(t))
      .toList();
}

// ── Los cuatro casos del modelo de identidad ───────────────────────────────
//
// Van APARTE de las cien, no mezclados adentro: [cienPersonas] promete cien
// personas naturales con cédula desde su propio nombre y su comentario, y
// agregar acá cuatro entradas de otra forma lo volvería falso para quien lo
// lea sin mirar el final del archivo. `main.dart` junta las dos listas para
// que las cuatro sean seleccionables en la pantalla del demo.

/// Dos empresas — `TipoDeSujeto.juridica`, con RIF.
const empresasDePrueba = <PersonaDePrueba>[
  PersonaDePrueba(
    userId: 'empresa1-J304521679',
    usuario: 'empresa1',
    cedula: 'J-304521679',
    correo: 'compras@distribuidoraelfaro.com.ve',
    nombre: 'Distribuidora El Faro, C.A.',
    sucursal: 'CCS-01',
    ciudad: 'Caracas',
    plan: 'Empresas',
    tipo: TipoDeSujeto.juridica,
    claseDeDocumento: ClaseDeDocumento.rif,
  ),
  PersonaDePrueba(
    userId: 'empresa2-J403187745',
    usuario: 'empresa2',
    cedula: 'J-403187745',
    correo: 'administracion@construval.com.ve',
    nombre: 'Construval Ingeniería, C.A.',
    sucursal: 'VAL-02',
    ciudad: 'Valencia',
    plan: 'Empresas',
    tipo: TipoDeSujeto.juridica,
    claseDeDocumento: ClaseDeDocumento.rif,
  ),
];

/// Dos empleados de un proveedor — naturales, con [Organizacion]. El sujeto
/// PERTENECE a la organización, no se reemplaza por ella: sigue teniendo su
/// propia cédula y su propio `userId`.
const empleadosDeProveedorDePrueba = <PersonaDePrueba>[
  PersonaDePrueba(
    userId: 'empleado1-19988341',
    usuario: 'empleado1',
    cedula: '19988341',
    correo: 'jgimenez@logisticasur.com.ve',
    nombre: 'Julio Giménez',
    sucursal: 'MCB-02',
    ciudad: 'Maracaibo',
    plan: 'Empleados',
    organizacion: Organizacion(
      codigo: 'prov-logisticasur',
      nombre: 'Logística Sur, C.A.',
      rol: 'repartidor',
    ),
  ),
  PersonaDePrueba(
    userId: 'empleado2-20214477',
    usuario: 'empleado2',
    cedula: '20214477',
    correo: 'mtovar@logisticasur.com.ve',
    nombre: 'Mariana Tovar',
    sucursal: 'MCB-02',
    ciudad: 'Maracaibo',
    plan: 'Empleados',
    organizacion: Organizacion(
      codigo: 'prov-logisticasur',
      nombre: 'Logística Sur, C.A.',
      rol: 'supervisora',
    ),
  ),
];

/// Las cuatro juntas, para ofrecerlas en la pantalla del demo junto con las
/// cien. Ver la nota de arriba sobre por qué no van adentro de [cienPersonas].
const casosDeIdentidadDePrueba = <PersonaDePrueba>[
  ...empresasDePrueba,
  ...empleadosDeProveedorDePrueba,
];
