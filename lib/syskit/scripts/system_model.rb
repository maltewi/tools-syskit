require 'roby/standalone'
require 'optparse'
require 'orocos'
require 'orocos/roby'
require 'orocos/roby/app'

def qt_layout_composition(scene, model, bounding_box, positions)
    result = []

    id = model.object_id.to_s

    rect = scene.add_rect(*bounding_box)
    model_name = scene.add_simple_text model.name
    model_name.pos = Qt::PointF.new(bounding_box[0], bounding_box[1])
    model_name.set_parent_item rect

    font = Qt::Font.new
    font.set_point_size(8)
    metrics = Qt::FontMetrics.new(font)

    model.each_child do |child_name, child_model|
        p = positions["C#{id}#{child_name}"]
        name       = scene.addText child_name, font
        model_name = scene.addText child_model.models.map(&:name).join(","), font

        name.pos       = Qt::PointF.new(p.x - name.bounding_rect.width / 2,
                                        p.y)
        model_name.pos = Qt::PointF.new(p.x - model_name.bounding_rect.width / 2,
                                        p.y + metrics.height)
    end
end

def produce_qt_layout(system_model, dot_layout)
    require 'Qt4'
    require 'roby/log/dot'
    app     = Qt::Application.new(ARGV)
    scene = Qt::GraphicsScene.new
    widget = Qt::GraphicsView.new(scene)

    bounding_rects, object_positions =
        Roby::LogReplay::RelationsDisplay::Layout.parse_dot_layout(dot_layout)
    system_model.each_composition do |model|
        bounding_box = bounding_rects[model.object_id.to_s]
        compositions = qt_layout_composition(scene, model, bounding_box, object_positions)
    end

    widget.show
    app.exec
end

output_type = 'txt'
output_file = nil
parser = OptionParser.new do |opt|
    opt.banner = <<-EOD
Usage: scripts/orocos/system_model [options] robot_name
Loads the models listed by robot_name, and outputs their model structure
    EOD
    opt.on('-o TYPE[:file]', '--output=TYPE[:file]', String, 'in what format to output the result (can be: txt, dot or svg), defaults to txt') do |output_arg|
        output_type, output_file = output_arg.split(':')
        output_type = output_type.downcase
        if output_type != 'txt' && !output_file
            STDERR.puts "you must specify an output file for the dot and svg outputs"
            exit(1)
        end
    end
    opt.on_tail('-h', '--help', 'this help message') do
	STDERR.puts opt
	exit
    end
end
remaining = parser.parse(ARGV)

# Load the models
Orocos::RobyPlugin.logger.level = Logger::INFO
Roby.filter_backtrace do
    Roby.app.setup
end

# Now output them
case output_type
when "txt"
    pp Roby.app.orocos_system_model
when "dot"
    File.open(output_file, 'w') do |output_io|
        output_io.puts Roby.app.orocos_system_model.to_dot
    end
when "qt"
    layout = nil
    Tempfile.open('roby_orocos_system_model') do |io|
        io.write Roby.app.orocos_system_model.to_dot
        io.flush
        layout = `dot -Tdot #{io.path}`
    end
    produce_qt_layout(Roby.app.orocos_system_model, layout)
when "svg"
    Tempfile.open('roby_orocos_system_model') do |io|
        io.write Roby.app.orocos_system_model.to_dot
        io.flush

        File.open(output_file, 'w') do |output_io|
            output_io.puts(`dot -Tsvg #{io.path}`)
        end
    end
end

